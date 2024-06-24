struct timed_packet {
    struct packet *packet;
    uint64_t sending_time;
};

struct delay_buffer {
  struct timed_packet *packets[128 * 1024];
  // Two cursors:
  //   read:  the next element to be read
  //   write: the next element to be written
  int read, write;
};
