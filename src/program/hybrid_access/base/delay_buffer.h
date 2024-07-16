enum
{
  DELAY_BUFFER_SIZE = 256 * 1024
};

struct timed_packet
{
  struct packet *packet;
  uint64_t sending_time;
};

struct delay_buffer
{
  struct timed_packet packets[DELAY_BUFFER_SIZE];
  // Two cursors:
  //   read:  the next element to be read
  //   write: the next element to be written
  int read;
  int write;
};

// Function prototypes
struct delay_buffer *db_new();
int db_enqueue(struct delay_buffer *buffer, struct packet *pkt, uint64_t sending_time);
struct packet *db_dequeue(struct delay_buffer *buffer);
uint64_t db_peek_time(struct delay_buffer *buffer);
int db_size(struct delay_buffer *buffer);
void db_free(struct delay_buffer *buffer);
