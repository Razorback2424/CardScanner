#ifndef TCS_CENTERING_PIXEL_KERNELS_H
#define TCS_CENTERING_PIXEL_KERNELS_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    float l;
    float a;
    float b;
} TCSCenteringPixel;

// Buffers are owned and sized by the Swift caller. These kernels only perform
// the existing scalar arithmetic; thresholds and selection stay in Swift.
void TCSCenteringConvertLab(const TCSCenteringPixel *rgb, TCSCenteringPixel *lab,
                           size_t count, const float *linearizedBytes);
void TCSCenteringDecodeRGBA(const uint8_t *bytes, TCSCenteringPixel *rgb, size_t count);
void TCSCenteringVerticalScores(const float *gradient, int stride,
                               int xStart, int xEnd, int yStart, int yEnd, float *scores);
void TCSCenteringHorizontalScores(const float *gradient, int stride,
                                 int xStart, int xEnd, int yStart, int yEnd, float *scores);
void TCSCenteringSilhouetteRow(const TCSCenteringPixel *row, int width,
                              TCSCenteringPixel left, TCSCenteringPixel right,
                              long *columnCounts);
// Finite image-derived samples; sorts the caller's scratch copy in place.
float TCSCenteringMedianFloat(float *samples, size_t count);
double TCSCenteringMedianDouble(double *samples, size_t count);
void TCSCenteringGradients(const TCSCenteringPixel *lab, int width, int height,
                          float *gx, float *gy);
void TCSCenteringForeground(const TCSCenteringPixel *lab, int width, int height,
                           TCSCenteringPixel background, float threshold,
                           long *columnCounts, long *rowCounts,
                           long *firstForeground, long *lastForeground);

#endif
