// unused
enum { BUFFER_SIZE = 16 * 1024 };

struct buffer {
  struct packet *packets[BUFFER_SIZE];
  int read;
  int write;
};

// Function prototypes
struct buffer* buffer_new();
int buffer_enqueue(struct buffer *buffer, struct packet *pkt);
struct packet* buffer_dequeue(struct buffer *buffer);
int buffer_size(struct buffer *buffer);
void buffer_free(struct buffer *buffer);
