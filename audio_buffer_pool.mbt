///|
pub struct AudioBufferPool[B, G] {
  arena : Arena[B, G]
  frames_per_buffer : Int
  channels : Int
}

///|
pub fn AudioBufferPool::new(
  frames_per_buffer : Int,
  channels : Int,
  buffer_count : Int,
) -> AudioBufferPool[MbBump, MbGenStore] {
  let slot_size = if frames_per_buffer <= 0 || channels <= 0 {
    0
  } else if frames_per_buffer > @int.max_value / channels {
    0
  } else {
    let samples = frames_per_buffer * channels
    if samples > @int.max_value / 8 {
      0
    } else {
      samples * 8
    }
  }
  let (capacity, max_slots) = if slot_size <= 0 || buffer_count <= 0 {
    (0, 0)
  } else if buffer_count > @int.max_value / slot_size {
    (0, 0)
  } else {
    (buffer_count * slot_size, buffer_count)
  }
  {
    arena: Arena::new_with(
      MbBump::new(capacity),
      MbGenStore::new(max_slots),
      slot_size,
      max_slots,
    ),
    frames_per_buffer: if slot_size == 0 {
      0
    } else {
      frames_per_buffer
    },
    channels: if slot_size == 0 {
      0
    } else {
      channels
    },
  }
}

///|
pub fn[B : BumpAllocator, G : GenStore] AudioBufferPool::new_with(
  bump : B,
  gen_store : G,
  frames_per_buffer : Int,
  channels : Int,
  max_buffers : Int,
) -> AudioBufferPool[B, G] {
  let slot_size = if frames_per_buffer <= 0 || channels <= 0 {
    0
  } else if frames_per_buffer > @int.max_value / channels {
    0
  } else {
    let samples = frames_per_buffer * channels
    if samples > @int.max_value / 8 {
      0
    } else {
      samples * 8
    }
  }
  {
    arena: Arena::new_with(bump, gen_store, slot_size, max_buffers),
    frames_per_buffer: if slot_size == 0 {
      0
    } else {
      frames_per_buffer
    },
    channels: if slot_size == 0 {
      0
    } else {
      channels
    },
  }
}

///|
pub fn[B : BumpAllocator, G : GenStore] AudioBufferPool::alloc(
  self : AudioBufferPool[B, G],
) -> BufferRef? {
  match self.arena.alloc() {
    None => None
    Some(r) => Some(BufferRef::{ inner: r })
  }
}

///|
pub fn[B : BumpAllocator, G : GenStore] AudioBufferPool::write_sample(
  self : AudioBufferPool[B, G],
  bref : BufferRef,
  frame : Int,
  channel : Int,
  value : Double,
) -> Bool {
  if frame < 0 ||
    frame >= self.frames_per_buffer ||
    channel < 0 ||
    channel >= self.channels {
    return false
  }
  let sample_index = frame * self.channels + channel
  let field_offset = sample_index * 8
  self.arena.write_double(bref.inner, field_offset, value)
}

///|
pub fn[B : BumpAllocator, G : GenStore] AudioBufferPool::read_sample(
  self : AudioBufferPool[B, G],
  bref : BufferRef,
  frame : Int,
  channel : Int,
) -> Double? {
  if frame < 0 ||
    frame >= self.frames_per_buffer ||
    channel < 0 ||
    channel >= self.channels {
    return None
  }
  let sample_index = frame * self.channels + channel
  let field_offset = sample_index * 8
  self.arena.read_double(bref.inner, field_offset)
}

///|
pub fn[B : BumpAllocator, G] AudioBufferPool::reset(
  self : AudioBufferPool[B, G],
) -> Unit {
  self.arena.reset()
}

///|
pub fn[B, G : GenStore] AudioBufferPool::is_valid(
  self : AudioBufferPool[B, G],
  bref : BufferRef,
) -> Bool {
  self.arena.is_valid(bref.inner)
}

///|
pub fn[B, G] AudioBufferPool::get_frames_per_buffer(
  self : AudioBufferPool[B, G],
) -> Int {
  self.frames_per_buffer
}

///|
pub fn[B, G] AudioBufferPool::get_channels(self : AudioBufferPool[B, G]) -> Int {
  self.channels
}
