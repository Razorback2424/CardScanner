#include "CardCenteringPixelKernels.h"
#include <math.h>
#include <stdlib.h>

// Compiled with strict floating-point contraction disabled. Match the Swift
// Float expressions and their order, including powf rather than approximations.
static float labCurve(float value) {
    return value > 0.008856f ? powf(value, 1.0f / 3.0f) : 7.787f * value + 16.0f / 116.0f;
}

static float pixelDistance(TCSCenteringPixel first, TCSCenteringPixel second) {
    float l = first.l - second.l;
    float a = first.a - second.a;
    float b = first.b - second.b;
    return sqrtf(l * l + a * a + b * b);
}

void TCSCenteringDecodeRGBA(const uint8_t *bytes, TCSCenteringPixel *rgb, size_t count) {
    for (size_t index = 0; index < count; index++) {
        rgb[index] = (TCSCenteringPixel){(float)bytes[index * 4] / 255.0f,
                                      (float)bytes[index * 4 + 1] / 255.0f,
                                      (float)bytes[index * 4 + 2] / 255.0f};
    }
}

void TCSCenteringVerticalScores(const float *gradient, int stride,
                               int xStart, int xEnd, int yStart, int yEnd, float *scores) {
    float divisor = (float)(yEnd > yStart ? yEnd - yStart : 1);
    for (int x = xStart; x < xEnd; x++) {
        float total = 0;
        for (int y = yStart; y < yEnd; y++) total += gradient[y * stride + x];
        scores[x - xStart] = total / divisor;
    }
}

void TCSCenteringHorizontalScores(const float *gradient, int stride,
                                 int xStart, int xEnd, int yStart, int yEnd, float *scores) {
    float divisor = (float)(xEnd > xStart ? xEnd - xStart : 1);
    for (int y = yStart; y < yEnd; y++) {
        float total = 0;
        for (int x = xStart; x < xEnd; x++) total += gradient[y * stride + x];
        scores[y - yStart] = total / divisor;
    }
}

void TCSCenteringSilhouetteRow(const TCSCenteringPixel *row, int width,
                              TCSCenteringPixel left, TCSCenteringPixel right,
                              long *columnCounts) {
    for (int x = 0; x < width; x++) {
        float progress = (float)x / (float)(width > 1 ? width - 1 : 1);
        TCSCenteringPixel background = {left.l + progress * (right.l - left.l),
                                      left.a + progress * (right.a - left.a),
                                      left.b + progress * (right.b - left.b)};
        if (pixelDistance(row[x], background) >= 8.0f) columnCounts[x]++;
    }
}

static int compareFloat(const void *first, const void *second) {
    float a = *(const float *)first, b = *(const float *)second;
    return (a > b) - (a < b);
}

static int compareDouble(const void *first, const void *second) {
    double a = *(const double *)first, b = *(const double *)second;
    return (a > b) - (a < b);
}

float TCSCenteringMedianFloat(float *samples, size_t count) {
    if (count == 0) return 0;
    qsort(samples, count, sizeof(float), compareFloat);
    size_t middle = count / 2;
    return count % 2 == 0 ? (samples[middle - 1] + samples[middle]) / 2.0f : samples[middle];
}

double TCSCenteringMedianDouble(double *samples, size_t count) {
    if (count == 0) return 0;
    qsort(samples, count, sizeof(double), compareDouble);
    size_t middle = count / 2;
    return count % 2 == 0 ? (samples[middle - 1] + samples[middle]) / 2.0 : samples[middle];
}

void TCSCenteringConvertLab(const TCSCenteringPixel *rgb, TCSCenteringPixel *lab,
                           size_t count, const float *linearizedBytes) {
    for (size_t index = 0; index < count; index++) {
        float r = linearizedBytes[(int)roundf(rgb[index].l * 255.0f)];
        float g = linearizedBytes[(int)roundf(rgb[index].a * 255.0f)];
        float b = linearizedBytes[(int)roundf(rgb[index].b * 255.0f)];
        float x = (0.4124564f * r + 0.3575761f * g + 0.1804375f * b) / 0.95047f;
        float y = 0.2126729f * r + 0.7151522f * g + 0.0721750f * b;
        float z = (0.0193339f * r + 0.1191920f * g + 0.9503041f * b) / 1.08883f;
        float fx = labCurve(x), fy = labCurve(y), fz = labCurve(z);
        lab[index] = (TCSCenteringPixel){116.0f * fy - 16.0f, 500.0f * (fx - fy), 200.0f * (fy - fz)};
    }
}

void TCSCenteringGradients(const TCSCenteringPixel *lab, int width, int height,
                          float *gx, float *gy) {
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width - 1; x++) {
            gx[y * (width - 1) + x] = pixelDistance(lab[y * width + x], lab[y * width + x + 1]);
        }
    }
    for (int y = 0; y < height - 1; y++) {
        for (int x = 0; x < width; x++) {
            gy[y * width + x] = pixelDistance(lab[y * width + x], lab[(y + 1) * width + x]);
        }
    }
}

void TCSCenteringForeground(const TCSCenteringPixel *lab, int width, int height,
                           TCSCenteringPixel background, float threshold,
                           long *columnCounts, long *rowCounts,
                           long *firstForeground, long *lastForeground) {
    for (int y = 0; y < height; y++) {
        int row = y * width;
        for (int x = 0; x < width; x++) {
            if (pixelDistance(lab[row + x], background) >= threshold) {
                columnCounts[x]++;
                rowCounts[y]++;
                if (firstForeground[y] < 0) firstForeground[y] = x;
                lastForeground[y] = x;
            }
        }
    }
}
