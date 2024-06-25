#define QUEUE_SIZE (32 * 1024)

#include <stdint.h>

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
struct ring_buffer* create_buffer();
inline int is_empty(struct ring_buffer *buffer);
inline int is_full(struct ring_buffer *buffer);
void enqueue(struct ring_buffer *buffer, struct packet *pkt, uint64_t sending_time);
struct timed_packet* dequeue(struct ring_buffer *buffer);
uint64_t peek_time(struct ring_buffer *buffer);
int buffer_size(struct ring_buffer *buffer);
void free_buffer(struct ring_buffer *buffer);
