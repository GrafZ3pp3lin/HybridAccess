#include <stdint.h>
#include <stdlib.h>
#include "ring_queue.h"

// Initialize the delay buffer
struct ring_buffer* create_buffer() {
    struct ring_buffer *buffer = (struct ring_buffer*) malloc(sizeof(struct ring_buffer));
    if (buffer) {
        buffer->read = 0;
        buffer->write = 0;
    }
    return buffer;
}

// Check if the buffer is empty
inline int is_empty(struct ring_buffer *buffer) {
    return buffer->read == buffer->write;
}

// Check if the buffer is full
inline int is_full(struct ring_buffer *buffer) {
    return ((buffer->write + 1) & (QUEUE_SIZE - 1)) == buffer->read;
}

// Enqueue a timed packet to the buffer
// not full check needs to be done
void enqueue(struct ring_buffer *buffer, struct packet *pkt, uint64_t sending_time) {
    // assert not full
    buffer->packets[buffer->write].packet = pkt;
    buffer->packets[buffer->write].sending_time = sending_time;

    buffer->write = (buffer->write + 1) & (QUEUE_SIZE - 1);
}

// Dequeue a timed packet from the buffer
// not empty check needs to be done
struct timed_packet* dequeue(struct ring_buffer *buffer) {
    // assert not empty
    struct timed_packet *pkt = &(buffer->packets[buffer->read]);
    buffer->read = (buffer->read + 1) & (QUEUE_SIZE - 1);
    return pkt;
}

// Peek at the sending time of the next timed packet to be read without removing it from the buffer
uint64_t peek_time(struct ring_buffer *buffer) {
    if (is_empty(buffer)) {
        // Buffer is empty
        return UINT64_MAX;
    }
    return buffer->packets[buffer->read].sending_time;
}

// Amount of readable packets
int buffer_size(struct ring_buffer *buffer) {
    if (buffer->write > buffer->read) {
        return buffer->write - buffer->read;
    }
    return buffer->write + QUEUE_SIZE - buffer->read;
}

// Destroy the delay buffer and free its memory
void free_buffer(struct ring_buffer *buffer) {
    if (buffer) {
        free(buffer);
    }
}