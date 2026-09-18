require "./index"
require "./contracts"
require "./type_utils"
require "./summary"

module Crystalline::Lightweight
  # Answers lookup queries over a project index, optionally overlaid with a
  # per-file source index (a dirty buffer diverging from the compiled
  # sources). The overlay is consulted first so redefinitions in the buffer
  # win, without copying or merging the whole project index per keystroke.
  class Query
    # Compiler hierarchy roots whose own indexed methods lack the
    # accessors defined on their subclasses: `Crystal::ASTNode` carries
    # no `name`/`body`/`args` while `Var`/`Def`/`Block` do. Only these
    # bases get the subtype-method fallback (see methods_named).
    def self.subtype_fallback_type?(type_name : String) : Bool
      case type_name
      when "Crystal::ASTNode", "Crystal::Type", "Crystal::NamedType"
        true
      else
        false
      end
    end

    # Memoized lookups; queries are immutable after construction.
    @methods_cache : Hash(String, Array(MethodInfo))? = nil
    @contracts_cache : Hash(String, Array(MethodContract))? = nil
    @all_type_names_cache : Array(String)? = nil
    @subtype_methods_cache : Hash(String, Array(MethodInfo))? = nil
    @subtypes_index : Hash(String, Array(String))? = nil
    # The inference walker's untyped-arg seeding result per def (keyed by
    # the def's source location): cursor-independent, so repeated
    # requests on the same buffer skip the whole call-site scan.
    @untyped_arg_types : Hash(String, Hash(String, Array(String)))? = nil

    def initialize(@index : Index, @summary : Summary? = nil, @overlay : Index? = nil, @secondary : Index? = nil)
    end

    def cached_untyped_arg_types(key : String) : Hash(String, Array(String))?
      @untyped_arg_types.try(&.[key]?)
    end

    def cache_untyped_arg_types(key : String, types : Hash(String, Array(String)))
      (@untyped_arg_types ||= {} of String => Hash(String, Array(String)))[key] = types
    end

    def find_type(name : String) : TypeInfo?
      overlay_type(name) || preferred_type(name) || generic_specialization_for(name).try(&.[0])
    end

    # The compiled-program index keys generic classes twice: the bare name
    # carries only a few synthesized methods (`==`, `new`, `to_json`, ...)
    # while the template (`Hash(K, V)`) carries the real defs. When both
    # exist, prefer the template so `Hash#empty?`-style lookups resolve.
    private def preferred_type(name : String) : TypeInfo?
      exact = @index.types[name]? || @secondary.try(&.types[name]?)
      return exact unless exact

      candidate_name = generic_candidate_names(name).sort_by(&.size).first?
      return exact unless candidate_name

      candidate = @index.types[candidate_name]? || @secondary.try(&.types[candidate_name]?)
      candidate && candidate.methods.size > exact.methods.size ? candidate : exact
    end

    # Finds a type by its bare name, falling back to the first generic
    # specialization (`Dispatcher` → `Dispatcher(T)`), which is how the
    # source index keys generic classes.
    def find_type_info(name : String) : TypeInfo?
      find_type(name) || begin
        found = nil
        # Try every candidate, not just the shortest: the summary's
        # generic keys (`Proc(T)`) can shadow the real template
        # (`Proc(*T, R)`) in an index, and the shadow may not resolve.
        generic_candidate_names(name.split('(').first? || name).sort_by(&.size).each do |candidate|
          if type = find_type(candidate)
            found = type
            break
          end
        end
        found
      end
    end

    def resolve_type_name(name : String, namespace : String? = nil) : String?
      normalized = name.strip
      normalized = normalized.lchop("::")

      # Lexical resolution: a name defined in the enclosing namespace
      # shadows the top-level one (`Priority::Value` beats the stdlib's
      # root `struct Value`), so try the qualified candidates before the
      # bare-known fast path.
      if namespace
        namespace_candidates(namespace).each do |prefix|
          candidate = "#{prefix}::#{normalized}"
          return candidate if known_type_name?(candidate)
        end
      end

      return normalized if known_type_name?(normalized)

      suffix_matches = all_type_names.select do |candidate|
        candidate == normalized || candidate.ends_with?("::#{normalized}")
      end
      if suffix_matches.size == 1
        suffix_matches.first
      elsif suffix_matches.size > 1 && namespace
        # Ambiguous bare name (`Location` is both `Crystal::Location` and
        # `Time::Location`): prefer the candidate sharing the longest
        # namespace prefix with the enclosing type, the way the compiler's
        # lexical resolution would pick the closest definition.
        best = suffix_matches.first
        best_score = common_prefix_length(best, namespace.not_nil!)
        suffix_matches.each do |candidate|
          score = common_prefix_length(candidate, namespace.not_nil!)
          if score > best_score
            best = candidate
            best_score = score
          end
        end
        common_prefix_length(best, namespace) > 0 ? best : nil
      elsif suffix_matches.empty? && !normalized.includes?('(')
        # A bare generic name (`Channel`) resolves to its first
        # specialization (`Channel(T)`), like the index keys it.
        generic_candidate_names(normalized).sort_by(&.size).first?
      end
    end

    private def common_prefix_length(name_a : String, name_b : String) : Int32
      index = 0
      while index < name_a.size && index < name_b.size && name_a[index] == name_b[index]
        index += 1
      end
      index
    end

    def methods_for(type_name : String, *, class_method = false, include_macros = false) : Array(MethodInfo)
      # Queries are immutable after construction: memoize the hierarchy walk
      # so repeated lookups for the same type in one request are free.
      cache_key = "#{type_name}:#{class_method}:#{include_macros}"
      if cached = (@methods_cache ||= {} of String => Array(MethodInfo))[cache_key]?
        return cached
      end

      methods = methods_for(type_name, class_method: class_method, include_macros: include_macros, visited: Set(String).new)
      if methods.empty?
        if !type_name.includes?('(')
          # The source index keys generic classes as `Dispatcher(T)`: a bare
          # `Dispatcher` lookup falls back to the first specialization so
          # self-calls, getters and hovers resolve on generic types too.
          generic_candidate_names(type_name).sort_by(&.size).each do |candidate|
            methods = methods_for(candidate, class_method: class_method, include_macros: include_macros, visited: Set(String).new)
            break unless methods.empty?
          end
        end
        if methods.empty? && (base_name = type_name.split('(').first?) && base_name != type_name
          # A specialization like `Proc(String, URI, String)` (e.g. the
          # target of an alias) resolves through the generic template
          # `Proc(*T, R)`.
          methods = methods_for(base_name, class_method: class_method, include_macros: include_macros, visited: Set(String).new)
        end
      end
      # The compiled index records macro-generated defs (delegate
      # passthroughs like `def shift(*args, **kwargs)`) with no declared
      # return type; the semantic summary captured the compiler-inferred
      # returns per instantiation. Fill the nil returns so chains through
      # delegated methods keep resolving post-compile.
      methods = fill_summary_returns(methods, type_name)
      @methods_cache.not_nil![cache_key] = methods
      methods
    end

    # Replaces nil method returns with the summary's compiler-inferred
    # returns for the same name and arity (the summary is keyed per
    # instantiation, so its returns are already concrete — no free-var
    # substitution; the arity guard keeps overloads distinct).
    private def fill_summary_returns(methods : Array(MethodInfo), type_name : String) : Array(MethodInfo)
      return methods unless @summary
      summary_methods = summary_types_for(type_name).flat_map(&.methods)
      if summary_methods.empty? && type_name.includes?("(::")
        # Compiled returns render generic args `::`-prefixed
        # (`Priority::Item(::Tuple(...))`) while the summary keys them
        # plain: retry with the normalized name.
        summary_methods = summary_types_for(type_name.gsub("(::", "(")).flat_map(&.methods)
      end
      return methods if summary_methods.empty?
      summary_returns = {} of String => String
      summary_methods.each do |sm|
        next unless return_type = sm.return_type
        key = "#{sm.name}:#{sm.class_method}:#{sm.args.size}"
        summary_returns[key] = return_type unless summary_returns.has_key?(key)
      end
      methods.map do |method|
        next method unless method.return_type.nil?
        key = "#{method.name}:#{method.class_method}:#{method.args.size}"
        if return_type = summary_returns[key]?
          method.copy_with(return_type: return_type)
        else
          method
        end
      end
    end

    def subtypes_for(type_name : String) : Array(String)
      subtypes = [] of String
      if type = overlay_type(type_name)
        subtypes.concat(type.subtypes)
      end
      if type = @index.types[type_name]?
        subtypes.concat(type.subtypes)
      elsif secondary = @secondary.try(&.types[type_name]?)
        subtypes.concat(secondary.subtypes)
      end
      subtypes.uniq
    end

    # The BFS distance from *from* to every reachable type in the
    # recorded parent graph (0 = the type itself, 1 = a direct parent or
    # included module, ...). Completion ranks methods by their owner's
    # distance — computed once per receiver type per request instead of
    # once per method (per-method BFSes with a find_type_info miss scan
    # made completion O(methods × type-key scan)).
    def type_hierarchy_depths(from : String) : Hash(String, Int32)
      depths = {from => 0}
      queue = [from]
      until queue.empty?
        current = queue.shift
        depth = depths[current]
        type = find_type_info(current)
        next unless type
        type.parent_types.each do |parent|
          next if depths.has_key?(parent)
          depths[parent] = depth + 1
          queue << parent
        end
      end
      depths
    end

    def top_level_methods : Array(MethodInfo)
      methods = @index.top_level_methods.dup
      if secondary_methods = @secondary.try(&.top_level_methods)
        secondary_methods.each do |method|
          next if methods.any? { |existing| Index.same_method?(existing, method) }
          methods << method
        end
      end
      if overlay_methods = @overlay.try(&.top_level_methods)
        overlay_methods.each do |method|
          next if methods.any? { |existing| Index.same_method?(existing, method) }
          methods << method
        end
      end
      methods
    end

    def all_types : Array(TypeInfo)
      types = @index.types.values.to_a
      [@overlay, @secondary].each do |extra|
        next unless extra
        extra.types.each do |name, type|
          next if types.any? { |existing| existing.name == name }
          types << type
        end
      end
      types
    end

    def method_contracts_for(type_name : String, method_name : String, *, class_method = false) : Array(MethodContract)
      # A union receiver (`first?` → `Greeter | Nil`) has no entry of its
      # own: the contracts are the union of each member's. Only top-level
      # separators split (`Array(A | B)` keeps its nested union intact),
      # and the recursion only fires when the split actually happened.
      if type_name.includes?(" | ")
        top_parts = TypeUtils.split_top_level(type_name, '|')
        if top_parts.size > 1
          return top_parts.flat_map { |part| method_contracts_for(part, method_name, class_method: class_method) }.uniq
        end
      end

      cache_key = "#{type_name}:#{method_name}:#{class_method}"
      if cached = (@contracts_cache ||= {} of String => Array(MethodContract))[cache_key]?
        return cached
      end

      contracts = [] of MethodContract
      summary_types_for(type_name).each do |summary_type|
        summary_type.method_contracts[method_name]?.try(&.each do |contract|
          next unless contract.class_method == class_method
          contracts << contract unless contracts.includes?(contract)
        end)
      end

      methods_for(type_name, class_method: class_method).select(&.name.==(method_name)).each do |method|
        Contracts.derive(type_name, method).each do |contract|
          contracts << contract unless contracts.includes?(contract)
        end

        # A compiled concrete def may have lost its block restriction
        # (the compiler drops it after typing): derive from the generic
        # declaration (`Hash(K, V)` for `Hash(String, Greeter)`).
        if method.block_restriction.nil?
          if specialization = generic_specialization_for(type_name)
            generic_type, mapping = specialization
            generic_method = generic_type.methods.find do |candidate|
              candidate.name == method.name && candidate.class_method == method.class_method
            end
            if generic_method
              Contracts.derive(type_name, specialize_method(generic_method, owner_name: type_name, mapping: mapping)).each do |contract|
                contracts << contract unless contracts.includes?(contract)
              end
            end
          end
        end
      end

      @contracts_cache.not_nil![cache_key] = contracts
      contracts
    end

    def instance_var_types_for(type_name : String, var_name : String) : Array(String)
      summary_types_for(type_name).each do |summary_type|
        if types = summary_type.instance_vars[var_name]?
          return types
        end
      end
      [] of String
    end

    def class_var_types_for(type_name : String, var_name : String) : Array(String)
      summary_types_for(type_name).each do |summary_type|
        if types = summary_type.class_vars[var_name]?
          return types
        end
      end
      [] of String
    end

    def instance_vars_for(type_name : String) : Hash(String, Array(String))
      summary_types_for(type_name).each do |summary_type|
        return normalize_ivar_keys(summary_type.instance_vars, class_var: false) if summary_type.instance_vars.any?
      end

      ivars = (overlay_type(type_name) || @index.types[type_name]? || @secondary.try(&.types[type_name]?)).try(&.ivars)
      return {} of String => Array(String) unless ivars

      # Parsed types are best-effort (`Mutex` for `Mutex.new`): resolve them
      # against the merged index so they match what methods_for expects.
      ivars.transform_values { |types| types.map { |t| resolve_type_name(t, namespace: type_name) || t }.uniq }
    end

    def class_vars_for(type_name : String) : Hash(String, Array(String))
      summary_types_for(type_name).each do |summary_type|
        return normalize_ivar_keys(summary_type.class_vars, class_var: true) if summary_type.class_vars.any?
      end

      class_vars = (overlay_type(type_name) || @index.types[type_name]? || @secondary.try(&.types[type_name]?)).try(&.class_vars)
      return {} of String => Array(String) unless class_vars

      class_vars.transform_values { |types| types.map { |t| resolve_type_name(t, namespace: type_name) || t }.uniq }
    end

    # The compiled program keys ivars without the `@` prefix; the inference
    # looks them up with it. Normalize so both sources line up.
    private def normalize_ivar_keys(vars : Hash(String, Array(String)), *, class_var : Bool) : Hash(String, Array(String))
      vars.transform_keys { |key| key.starts_with?("@") ? key : (class_var ? "@@#{key}" : "@#{key}") }.transform_values(&.dup)
    end

    private def known_type_name?(name : String) : Bool
      find_type(name) != nil
    end

    private def all_type_names : Array(String)
      @all_type_names_cache ||= begin
        names = @index.types.keys
        if secondary = @secondary
          names += secondary.types.keys
        end
        if overlay = @overlay
          names += overlay.types.keys
        end
        if summary = @summary
          names += summary.types.keys
        end
        names.uniq
      end
    end

    private def namespace_candidates(namespace : String) : Array(String)
      parts = namespace.split("::")
      candidates = [] of String
      while parts.any?
        candidates << parts.join("::")
        parts.pop
      end
      candidates
    end

    private def summary_types_for(type_name : String) : Array(SummaryType)
      types = [] of SummaryType
      if summary_type = @summary.try(&.type(type_name))
        types << summary_type
      end

      if specialization = generic_summary_specialization_for(type_name)
        summary_type, _ = specialization
        types << summary_type unless types.includes?(summary_type)
      end

      types
    end

    private def methods_for(type_name : String, *, class_method : Bool, include_macros : Bool, visited : Set(String)) : Array(MethodInfo)
      visit_key = "#{type_name}:#{class_method}:#{include_macros}"
      return [] of MethodInfo if visited.includes?(visit_key)
      visited << visit_key

      methods = [] of MethodInfo
      parent_types = [] of String

      if type = @index.types[type_name]?
        methods.concat(select_methods(type.methods, type, class_method, include_macros))
        parent_types.concat(type.parent_types)
        merge_delegated_methods(type, methods, class_method, include_macros, visited, nil, type_name)
      elsif specialization = generic_specialization_for(type_name)
        generic_type, mapping = specialization
        methods.concat(select_methods(generic_type.methods, generic_type, class_method, include_macros).map { |method|
          specialize_method(method, owner_name: type_name, mapping: mapping)
        })
        parent_types.concat(generic_type.parent_types.map do |parent_type|
          substitute_type_vars(parent_type, mapping).not_nil!
        end)
        merge_delegated_methods(generic_type, methods, class_method, include_macros, visited, mapping, type_name)
      elsif type = find_type(type_name)
        methods.concat(select_methods(type.methods, type, class_method, include_macros))
        parent_types.concat(type.parent_types)
      end

      # A project type may shadow a stdlib type of the same name (e.g. the
      # `class URI` extension in ext/uri.cr, which has no superclass):
      # merge the secondary's methods and parents so the full stdlib
      # surface stays available on the extended type.
      if secondary_type = @secondary.try(&.types[type_name]?)
        methods = merge_methods(methods, select_methods(secondary_type.methods, secondary_type, class_method, include_macros))
        parent_types.concat(secondary_type.parent_types)
      end

      # A dirty-buffer overlay redefines methods of a type: a same-signature
      # method wins when its location differs from the indexed one (the
      # user edited the definition), otherwise the indexed method is kept.
      if overlay_type = @overlay.try(&.types[type_name]?)
        overlay_methods = select_methods(overlay_type.methods, overlay_type, class_method, include_macros)
        overlay_methods.each do |method|
          next unless method.class_method == class_method && (include_macros || !method.macro)

          if existing_index = methods.index { |existing| Index.same_method?(existing, method) }
            existing = methods[existing_index]
            methods[existing_index] = method if existing.location != method.location
          else
            methods << method
          end
        end
        parent_types.concat(overlay_type.parent_types)
      end

      parent_types.uniq!
      parent_types.each do |parent_type|
        resolved_parent = resolve_parent_name(parent_type, type_name)
        # An alias to a union (`alias Value = Int8 | Int16 | ...`): split
        # it so each member's inherited methods (`Number#to_i32`) resolve
        # on the alias's receivers.
        if resolved_parent.includes?(" | ")
          union_parts = TypeUtils.split_top_level(resolved_parent, '|')
          if union_parts.size > 1
            union_parts.each do |part|
              methods = merge_methods(methods, methods_for(part.strip, class_method: class_method, include_macros: include_macros, visited: visited))
            end
            next
          end
        end
        methods = merge_methods(methods, methods_for(resolved_parent, class_method: class_method, include_macros: include_macros, visited: visited))
      end

      summary_types_for(type_name).each do |summary_type|
        methods = merge_methods(methods, summary_type.methods.select(&.class_method.==(class_method)))
      end
      if methods.empty? && parent_types.empty?
        if !type_name.includes?('(')
          # The source index keys generic classes as `Dispatcher(T)`: a
          # bare `Dispatcher` lookup falls back to the first
          # specialization so self-calls, getters and hovers resolve on
          # generic types too.
          generic_candidate_names(type_name).sort_by(&.size).each do |candidate|
            methods = methods_for(candidate, class_method: class_method, include_macros: include_macros, visited: visited)
            break unless methods.empty?
          end
        end
        if methods.empty? && (base_name = type_name.split('(').first?) && base_name != type_name
          # A specialization like `Proc(String, URI, String)` (e.g. the
          # target of an alias) resolves through the generic template
          # `Proc(*T, R)`.
          methods = methods_for(base_name, class_method: class_method, include_macros: include_macros, visited: visited)
        end
      end

      methods
    end

    # `delegate foo, to: @array` / `forward_missing_to @array` synthesize
    # no defs in the source parse: resolve the delegated names against the
    # target ivar's indexed type (`Array(Item(V))` → `first?`, `shift`, ...).
    private def merge_delegated_methods(type : TypeInfo, methods : Array(MethodInfo), class_method : Bool, include_macros : Bool, visited : Set(String), mapping : Hash(String, String)? = nil, receiver_name : String? = nil)
      return if type.delegates.empty? && type.forward_missing_to.nil?

      type.delegates.each do |delegate_name, target|
        delegate_target_methods(type, target, class_method, include_macros, visited, mapping, receiver_name).each do |method|
          next unless method.name == delegate_name
          methods << method unless methods.any? { |existing| Index.same_method?(existing, method) }
        end
      end

      if target = type.forward_missing_to
        delegate_target_methods(type, target, class_method, include_macros, visited, mapping, receiver_name).each do |method|
          methods << method unless methods.any? { |existing| Index.same_method?(existing, method) }
        end
      end
    end

    private def delegate_target_methods(type : TypeInfo, target : String, class_method : Bool, include_macros : Bool, visited : Set(String), mapping : Hash(String, String)? = nil, receiver_name : String? = nil) : Array(MethodInfo)
      return [] of MethodInfo unless target.starts_with?('@')
      target_types = type.ivars[target]? || type.class_vars[target]? || [] of String
      if target_types.empty?
        # The compiled index carries no ivars; the semantic summary does
        # (concrete per instantiation when the receiver is a
        # specialization).
        if receiver_name && receiver_name != type.name
          target_types = instance_vars_for(receiver_name)[target]? || [] of String
        end
        if target_types.empty?
          target_types = instance_vars_for(type.name)[target]? || type.class_vars[target]? || [] of String
        end
      end
      # The target's element type is usually a bare name (`Item(V)` inside
      # `Array(Item(V))`): resolve it against the receiver's namespace so
      # the delegated methods carry fully-qualified types.
      namespace = type.name.rpartition("::").first?
      target_types.flat_map do |target_type|
        # A generic receiver (`Priority::Queue(Change)`) specializes the
        # target's ivar type (`@array : Array(Priority::Item(V))` →
        # `Array(Priority::Item(Change))`) so the delegated methods return
        # the concrete element instead of the raw type var (`first?` →
        # `Priority::Item(Change) | ::Nil`).
        resolved_target = resolve_type_name_deep(target_type, namespace)
        substituted = mapping ? (substitute_type_vars(resolved_target, mapping) || resolved_target) : resolved_target
        # A fresh visited copy per call: the first delegate name's lookup
        # marks the target type as visited, which would silently empty every
        # later delegate's lookup (cycles are still guarded by the caller's
        # own key, which the copy carries over).
        methods_for(substituted, class_method: false, include_macros: include_macros, visited: visited.dup)
      end
    end

    # Resolves a type name against *namespace*, descending into generic
    # arguments: `Array(Item(V))` with bare nested names becomes
    # `Array(Priority::Item(V))` so the target lookups hit the
    # fully-qualified index entries.
    private def resolve_type_name_deep(type_name : String, namespace : String?) : String
      if (parts = TypeUtils.generic_type_arguments(type_name, "Array", 1)) && (element = parts[0]?)
        resolved_element = resolve_type_name_deep(element, namespace)
        return "Array(#{resolved_element})" if resolved_element != element
      end
      if (parts = TypeUtils.generic_type_arguments(type_name, "Hash", 2)) && parts.size == 2
        resolved_key = resolve_type_name_deep(parts[0], namespace)
        resolved_value = resolve_type_name_deep(parts[1], namespace)
        if resolved_key != parts[0] || resolved_value != parts[1]
          return "Hash(#{resolved_key}, #{resolved_value})"
        end
      end

      resolve_type_name(type_name, namespace: namespace) || type_name
    end

    # A base type's own methods may lack accessors that only exist on
    # its subclasses (`Crystal::ASTNode` carries no `name`/`body`/`args`
    # while `Var`/`Def`/`Block` do): when the direct lookup has no match
    # for *method_name*, fall back to the indexed subtypes' methods so
    # `node.name`-style receivers on compiler hierarchy roots still
    # resolve. Best effort: the dynamic type is unknown, but every
    # returned method is valid for some subtype.
    def methods_named(type_name : String, method_name : String, *, class_method : Bool, include_macros : Bool = false) : Array(MethodInfo)
      found = methods_for(type_name, class_method: class_method, include_macros: include_macros).select { |method| method.name == method_name }
      return found unless found.empty?
      return found unless Query.subtype_fallback_type?(type_name)

      subtype_methods_for(type_name, class_method: class_method, include_macros: include_macros).select { |method| method.name == method_name }
    end

    # A reverse-parent map built once: parent name (as recorded, plus its
    # bare last segment) -> direct subtype names. Bare keys let
    # `Crystal::ASTNode` find subtypes that record their parent as
    # `ASTNode`.
    private def subtypes_index : Hash(String, Array(String))
      @subtypes_index ||= begin
        index = {} of String => Array(String)
        all_indexes = [@index]
        @secondary.try { |secondary| all_indexes << secondary }
        @overlay.try { |overlay| all_indexes << overlay }
        all_indexes.each do |idx|
          idx.types.each do |name, type|
            type.parent_types.each do |parent|
              bare = parent.split("::").last?
              (index[parent] ||= [] of String) << name
              if bare && bare != parent
                (index[bare] ||= [] of String) << name
              end
            end
          end
        end
        index
      end
    end

    # The methods of a type's indexed subtypes (see methods_named). Exposed
    # for completion, which lists the full surface of hierarchy roots.
    def subtype_methods_for(type_name : String, *, class_method : Bool, include_macros : Bool) : Array(MethodInfo)
      cache_key = "#{type_name}:#{class_method}:#{include_macros}"
      cache = (@subtype_methods_cache ||= {} of String => Array(MethodInfo))
      if cached = cache[cache_key]?
        cached
      else
        collected = [] of MethodInfo
        visited = Set(String).new
        collect_subtype_methods(type_name, class_method: class_method, include_macros: include_macros, visited: visited, collected: collected)
        cache[cache_key] = collected
        collected
      end
    end

    private def collect_subtype_methods(type_name : String, *, class_method : Bool, include_macros : Bool, visited : Set(String), collected : Array(MethodInfo))
      return if visited.includes?(type_name)
      visited << type_name

      keys = [type_name, type_name.split("::").last?].compact
      subtype_names = keys.flat_map { |key| subtypes_index[key]? || [] of String }.uniq
      subtype_names.each do |subtype_name|
        next if visited.includes?(subtype_name)
        if subtype = @index.types[subtype_name]? || @secondary.try(&.types[subtype_name]?) || @overlay.try(&.types[subtype_name]?)
          collected.concat(select_methods(subtype.methods, subtype, class_method, include_macros))
        end
        collect_subtype_methods(subtype_name, class_method: class_method, include_macros: include_macros, visited: visited, collected: collected)
      end
    end

    private def overlay_type(name : String) : TypeInfo?
      @overlay.try(&.types[name]?)
    end

    # A module's instance methods are callable on the module itself
    # (`extend self`): offer them in the class-method view too, so
    # `Resolver.` and `TypeUtils.` completions work.
    private def select_methods(methods : Array(MethodInfo), type : TypeInfo, class_method : Bool, include_macros : Bool) : Array(MethodInfo)
      methods.select do |method|
        matches = method.class_method == class_method || (class_method && type.kind == TypeKind::Module)
        matches && (include_macros || !method.macro)
      end
    end

    private def generic_specialization_for(type_name : String) : {TypeInfo, Hash(String, String)}?
      generic_specialization(type_name) do |candidate_name|
        @overlay.try(&.types[candidate_name]?) || @index.types[candidate_name]? || @secondary.try(&.types[candidate_name]?)
      end
    end

    private def generic_summary_specialization_for(type_name : String) : {SummaryType, Hash(String, String)}?
      generic_specialization(type_name) do |candidate_name|
        @summary.try(&.type(candidate_name))
      end
    end

    private def generic_specialization(type_name : String, &resolver : String -> T?) forall T
      normalized = type_name.strip
      return unless open_index = normalized.index('(')
      return unless normalized.ends_with?(')')

      # The args between the first `(` and the last `)` must be balanced:
      # a nested-path name (`Priority::Queue(::Tuple(...))::Item(...)`)
      # has an extra `)` that would otherwise build a garbage 1:1 mapping
      # against the `Priority::Queue(V)` template.
      depth = 0
      normalized[open_index + 1...-1].each_char do |char|
        depth += 1 if char == '('
        depth -= 1 if char == ')'
        return if depth < 0
      end
      return unless depth == 0

      base_name = normalized[0, open_index]
      actual_args = TypeUtils.split_top_level(normalized[open_index + 1...-1], ',')

      generic_candidate_names(base_name).each do |candidate_name|
        candidate_params = TypeUtils.split_top_level(candidate_name[base_name.size + 1...-1], ',')
        mapping = build_generic_mapping(candidate_params, actual_args)
        next unless mapping

        if candidate = yield candidate_name
          return {candidate, mapping}
        end
      end

      nil
    end

    private def build_generic_mapping(candidate_params : Array(String), actual_args : Array(String)) : Hash(String, String)?
      if candidate_params.size == actual_args.size
        mapping = {} of String => String
        candidate_params.each_with_index do |param, index|
          mapping[param] = actual_args[index]
        end
        return mapping
      end

      # A leading splat with trailing params (`Proc(*T, R)`): the splat
      # takes the leading args, the trailing params the last ones.
      if (splat_param = candidate_params.first?) && splat_param.starts_with?('*')
        trailing = candidate_params.size - 1
        return unless actual_args.size >= trailing

        mapping = {} of String => String
        mapping[splat_param] = actual_args[0, actual_args.size - trailing].join(" | ")
        candidate_params[1..].each_with_index do |param, index|
          mapping[param] = actual_args[actual_args.size - trailing + index]
        end
        return mapping
      end

      nil
    end

    private def generic_candidate_names(base_name : String) : Array(String)
      candidates = @index.types.keys.select { |name| name.starts_with?("#{base_name}(") }
      if overlay = @overlay
        candidates.concat(overlay.types.keys.select { |name| name.starts_with?("#{base_name}(") })
      end
      if secondary = @secondary
        candidates.concat(secondary.types.keys.select { |name| name.starts_with?("#{base_name}(") })
      end
      if summary = @summary
        candidates.concat(summary.types.keys.select { |name| name.starts_with?("#{base_name}(") })
      end
      candidates.uniq
    end

    private def specialize_method(method : MethodInfo, owner_name : String, mapping : Hash(String, String)) : MethodInfo
      MethodInfo.new(
        name: method.name,
        owner: owner_name,
        args: method.args.map { |arg|
          ArgInfo.new(name: arg.name, restriction: substitute_type_vars(arg.restriction, mapping), splat: arg.splat)
        },
        return_type: substitute_type_vars(method.return_type, mapping),
        class_method: method.class_method,
        macro: method.macro,
        doc: method.doc,
        location: method.location,
        name_location: method.name_location,
        name_size: method.name_size,
        free_vars: method.free_vars,
        block_restriction: method.block_restriction.try { |restriction| substitute_type_vars(restriction, mapping) },
        double_splat: method.double_splat,
        block_arg: method.block_arg,
      )
    end

    private def substitute_type_vars(type_name : String?, mapping : Hash(String, String)) : String?
      return unless type_name

      TypeUtils.substitute_generic_params(type_name, mapping)
    end

    # The prelude records parent types by their bare name (`ASTNode`),
    # while types are keyed fully qualified (`Crystal::ASTNode`): resolve
    # the parent against the enclosing type's namespace so the hierarchy
    # walk reaches the indexed entry instead of silently returning empty.
    private def resolve_parent_name(parent_type : String, type_name : String) : String
      base_name = parent_type.split('(').first?
      return parent_type if base_name && base_name.includes?("::")
      namespace = type_name.rpartition("::").first?
      resolve_type_name(parent_type, namespace: namespace) || parent_type
    end

    private def merge_methods(base_methods : Array(MethodInfo), summary_methods : Array(MethodInfo)) : Array(MethodInfo)
      merged = base_methods.dup
      return merged if summary_methods.empty?

      # Index the base by identity so the merge is O(n + m) instead of a
      # linear scan per method (the subtype fallback merges thousands).
      existing_index = {} of String => Int32
      merged.each_with_index do |method, index|
        existing_index[method_merge_key(method)] = index
      end

      summary_methods.each do |summary_method|
        key = method_merge_key(summary_method)
        if index = existing_index[key]?
          existing = merged[index]
          merged[index] = MethodInfo.new(
            name: existing.name,
            owner: existing.owner,
            args: existing.args.empty? ? summary_method.args : existing.args,
            return_type: summary_method.return_type || existing.return_type,
            class_method: existing.class_method,
            macro: existing.macro,
            doc: existing.doc || summary_method.doc,
            location: existing.location || summary_method.location,
            name_location: existing.name_location || summary_method.name_location,
            name_size: existing.name_size.zero? ? summary_method.name_size : existing.name_size,
            free_vars: existing.free_vars.empty? ? summary_method.free_vars : existing.free_vars,
            block_restriction: existing.block_restriction || summary_method.block_restriction,
            double_splat: existing.double_splat || summary_method.double_splat,
            block_arg: existing.block_arg || summary_method.block_arg,
          )
        else
          existing_index[key] = merged.size
          merged << summary_method
        end
      end

      merged
    end

    private def method_merge_key(method : MethodInfo) : String
      "#{method.name}:#{method.class_method}:#{method.args.map(&.restriction).join("|")}"
    end
  end
end
