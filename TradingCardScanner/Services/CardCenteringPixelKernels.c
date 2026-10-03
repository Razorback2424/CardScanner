#include "CardCenteringPixelKernels.h"
#include <math.h>

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
