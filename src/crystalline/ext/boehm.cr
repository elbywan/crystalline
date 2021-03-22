module GC
  def self.init
    LibGC.set_free_space_divisor(10)
    LibGC.set_force_unmap_on_gcollect(1)
    previous_def
  end
end

lib LibGC
  fun set_free_space_divisor = GC_set_free_space_divisor(size : LibGC::Word) : Void
  fun enable_incremental = GC_enable_incremental : Void
  fun set_force_unmap_on_gcollect = GC_set_force_unmap_on_gcollect(size : LibC::Int) : Void
end
