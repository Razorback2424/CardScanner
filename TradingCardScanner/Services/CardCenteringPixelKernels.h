#ifndef TCS_CENTERING_PIXEL_KERNELS_H
#define TCS_CENTERING_PIXEL_KERNELS_H

#include <stddef.h>

typedef struct {
    float l;
    float a;
    float b;
} TCSCenteringPixel;

// Buffers are owned and sized by the Swift caller. These kernels only perform
// the existing scalar arithmetic; thresholds and selection stay in Swift.
void TCSCenteringConvertLab(const TCSCenteringPixel *rgb, TCSCenteringPixel *lab,
                           size_t count, const float *linearizedBytes);
void TCSCenteringGradients(const TCSCenteringPixel *lab, int width, int height,
                          float *gx, float *gy);
void TCSCenteringForeground(const TCSCenteringPixel *lab, int width, int height,
                           TCSCenteringPixel background, float threshold,
                           long *columnCounts, long *rowCounts,
                           long *firstForeground, long *lastForeground);

#endif
