#ifndef MTPBridge_h
#define MTPBridge_h
#include <libmtp.h>
#include <stdint.h>
typedef struct ATControl ATControl;
ATControl *ATControlCreate(void);
void ATControlDestroy(ATControl *control);
void ATControlCancel(ATControl *control);
int ATControlIsCancelled(ATControl *control);
uint64_t ATControlDone(ATControl *control);
uint64_t ATControlTotal(ATControl *control);
int ATDownload(LIBMTP_mtpdevice_t *device, uint32_t object, int fd, ATControl *control);
int ATUpload(LIBMTP_mtpdevice_t *device, int fd, LIBMTP_file_t *file, ATControl *control);
#endif
