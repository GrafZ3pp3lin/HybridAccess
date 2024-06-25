// Similar to C Packet
const PACKET_PAYLOAD_SIZE: usize = 10 * 1024;

#[repr(C)]
pub struct CPacket {
    pub length: u16,           // data payload length
    pub data: [u8; PACKET_PAYLOAD_SIZE],
}

impl Default for CPacket {
    fn default() -> Self {
        Self {
            length: Default::default(),
            data: [0; PACKET_PAYLOAD_SIZE],
        }
    }
}

#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct DelayedPacket {
    pub time_to_send: u64, // in ns
    pub packet_pointer: *const CPacket,
}

impl Default for DelayedPacket {
    fn default() -> Self {
        Self {
            time_to_send: Default::default(),
            packet_pointer: &Default::default(),
        }
    }
}

// Implementation of this RingQueue according to the Link implementation
// of Snabb in link.lua
const QUEUE_RING_SIZE: usize = 128 * 1024;

#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct RingQueue {
    buffer: [DelayedPacket; QUEUE_RING_SIZE],
    read: usize,
    write: usize,
}

impl Default for RingQueue {
    fn default() -> Self {
        Self::new()
    }
}

impl RingQueue {
    #[no_mangle]
    pub extern "C" fn new() -> RingQueue {
        RingQueue {
            buffer: [Default::default(); QUEUE_RING_SIZE],
            read: 0,
            write: 0,
        }
    }

    #[no_mangle]
    pub extern "C" fn free(self) {}

    #[no_mangle]
    pub extern "C" fn push(&mut self, time_to_send: u64, packet_pointer: *const CPacket) -> bool {
        if self.full() {
            return false;
        } else {
            let mut tuple = self.buffer[self.write];
            tuple.packet_pointer = packet_pointer;
            tuple.time_to_send = time_to_send;

            self.write = (self.write + 1) % QUEUE_RING_SIZE;
            return true;
        }
    }

    #[no_mangle]
    pub extern "C" fn pop(&mut self) -> *const CPacket {
        let tuple = self.buffer[self.read];
        self.read = (self.read + 1) % QUEUE_RING_SIZE;

        return tuple.packet_pointer;
    }

    #[no_mangle]
    pub extern "C" fn empty(&self) -> bool {
        return self.read == self.write;
    }

    #[no_mangle]
    pub extern "C" fn full(&self) -> bool {
        return self.read == (self.write + 1) % QUEUE_RING_SIZE;
    }

    #[no_mangle]
    pub extern "C" fn nreadable(&self) -> usize {
        if self.write > self.read {
            return self.write - self.read;
        } else {
            return self.write + QUEUE_RING_SIZE - self.read;
        }
    }

    #[no_mangle]
    pub extern "C" fn front_time(&self) -> u64 {
        if self.empty() {
            return u64::MAX;
        } else {
            return self.buffer[self.read].time_to_send;
        }
    }
}