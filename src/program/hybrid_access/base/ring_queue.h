enum { QUEUE_SIZE = 32 * 1024 };

struct timed_packet {
    struct packet *packet;
    uint64_t sending_time;
};

struct ring_buffer {
  struct timed_packet packets[QUEUE_SIZE];
  // Two cursors:
  //   read:  the next element to be read
  //   write: the next element to be written
  int read;
  int write;
};

// Function prototypes
struct ring_buffer* buffer_new();
int buffer_enqueue(struct ring_buffer *buffer, struct packet *pkt, uint64_t sending_time);
struct packet* buffer_dequeue(struct ring_buffer *buffer);
uint64_t buffer_peek_time(struct ring_buffer *buffer);
int buffer_size(struct ring_buffer *buffer);
void buffer_free(struct ring_buffer *buffer);
