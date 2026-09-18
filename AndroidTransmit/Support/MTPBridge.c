#include "MTPBridge.h"
#include <stdatomic.h>
#include <stdlib.h>
struct ATControl { atomic_int cancelled; atomic_uint_fast64_t done; atomic_uint_fast64_t total; };
ATControl *ATControlCreate(void) {
    ATControl *c = calloc(1, sizeof(ATControl));
    if (c) { atomic_init(&c->cancelled, 0); atomic_init(&c->done, 0); atomic_init(&c->total, 0); }
    return c;
}
void ATControlDestroy(ATControl *c) { free(c); }
void ATControlCancel(ATControl *c) { atomic_store(&c->cancelled, 1); }
int ATControlIsCancelled(ATControl *c) { return atomic_load(&c->cancelled); }
uint64_t ATControlDone(ATControl *c) { return atomic_load(&c->done); }
uint64_t ATControlTotal(ATControl *c) { return atomic_load(&c->total); }
static int progress(uint64_t done, uint64_t total, const void *data) {
    ATControl *c = (ATControl *)data;
    atomic_store(&c->done, done); atomic_store(&c->total, total);
    return atomic_load(&c->cancelled);
}
static void reset(ATControl *c) { atomic_store(&c->done, 0); atomic_store(&c->total, 0); }
int ATDownload(LIBMTP_mtpdevice_t *d, uint32_t object, int fd, ATControl *c) {
    reset(c);
    if (ATControlIsCancelled(c)) return -1;
    return LIBMTP_Get_File_To_File_Descriptor(d, object, fd, progress, c);
}
int ATUpload(LIBMTP_mtpdevice_t *d, int fd, LIBMTP_file_t *f, ATControl *c) {
    reset(c);
    if (ATControlIsCancelled(c)) return -1;
    return LIBMTP_Send_File_From_File_Descriptor(d, fd, f, progress, c);
}
