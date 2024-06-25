#include <stdlib.h>
#include "buffer.h"

// Initialize the delay buffer
struct buffer* buffer_new() {
    struct buffer *buffer = (struct buffer*) malloc(sizeof(struct buffer));
    if (buffer) {
        buffer->read = 0;
        buffer->write = 0;
    }
    return buffer;
}

// Check if the buffer is empty
inline int buffer_is_empty(struct buffer *buffer) {
    return buffer->read == buffer->write;
}

// Check if the buffer is full
inline int buffer_is_full(struct buffer *buffer) {
    return ((buffer->write + 1) & (BUFFER_SIZE - 1)) == buffer->read;
}

// Enqueue a timed packet to the buffer
// not full check needs to be done
int buffer_enqueue(struct buffer *buffer, struct packet *pkt) {
    if (buffer_is_full(buffer)) {
        return 0;
    }
    buffer->packets[buffer->write] = pkt;

    buffer->write = (buffer->write + 1) & (BUFFER_SIZE - 1);
    return 1;
}

// Dequeue a timed packet from the buffer
// not empty check needs to be done
struct packet* buffer_dequeue(struct buffer *buffer) {
    // assert not empty
    struct packet *pkt = buffer->packets[buffer->read];
    buffer->read = (buffer->read + 1) & (BUFFER_SIZE - 1);
    return pkt;
}

// Amount of readable packets
int buffer_size(struct buffer *buffer) {
    if (buffer->write >= buffer->read) {
        return buffer->write - buffer->read;
    }
    return buffer->write + BUFFER_SIZE - buffer->read;
}

// Destroy the delay buffer and free its memory
void buffer_free(struct buffer *buffer) {
    if (buffer) {
        free(buffer);
    }
}