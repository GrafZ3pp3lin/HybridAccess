#include <stdint.h>
#include <stdlib.h>
#include "delay_buffer.h"

// Initialize the delay buffer
struct delay_buffer* db_new() {
    struct delay_buffer *buffer = (struct delay_buffer*) malloc(sizeof(struct delay_buffer));
    if (buffer) {
        buffer->read = 0;
        buffer->write = 0;
    }
    return buffer;
}

// Check if the buffer is empty
inline int buffer_is_empty(struct delay_buffer *buffer) {
    return buffer->read == buffer->write;
}

// Check if the buffer is full
inline int buffer_is_full(struct delay_buffer *buffer) {
    return ((buffer->write + 1) & (DELAY_BUFFER_SIZE - 1)) == buffer->read;
}

// Enqueue a timed packet to the buffer
// not full check needs to be done
int db_enqueue(struct delay_buffer *buffer, struct packet *pkt, uint64_t sending_time) {
    if (buffer_is_full(buffer)) {
        return 0;
    }
    buffer->packets[buffer->write].packet = pkt;
    buffer->packets[buffer->write].sending_time = sending_time;

    buffer->write = (buffer->write + 1) & (DELAY_BUFFER_SIZE - 1);
    return 1;
}

// Dequeue a timed packet from the buffer
// not empty check needs to be done
struct packet* db_dequeue(struct delay_buffer *buffer) {
    // assert not empty
    struct timed_packet pkt = buffer->packets[buffer->read];
    buffer->read = (buffer->read + 1) & (DELAY_BUFFER_SIZE - 1);
    return pkt.packet;
}

// Peek at the sending time of the next timed packet to be read without removing it from the buffer
uint64_t db_peek_time(struct delay_buffer *buffer) {
    if (buffer_is_empty(buffer)) {
        // Buffer is empty
        return UINT64_MAX;
    }
    return buffer->packets[buffer->read].sending_time;
}

// Amount of readable packets
int db_size(struct delay_buffer *buffer) {
    if (buffer->write >= buffer->read) {
        return buffer->write - buffer->read;
    }
    return buffer->write + DELAY_BUFFER_SIZE - buffer->read;
}

// Destroy the delay buffer and free its memory
void db_free(struct delay_buffer *buffer) {
    if (buffer) {
        free(buffer);
    }
}