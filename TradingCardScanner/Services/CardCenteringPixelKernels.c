#include "CardCenteringPixelKernels.h"
#include <math.h>
#include <stdlib.h>

#ifdef DEBUG
// Corners are scaled raster-edge coordinates in TL, TR, BR, BL order.
void TCSCenteringSamplePrintGrid(const uint8_t *gray, int width, int height,
                                const double *p, uint8_t *grid) {
    for (int y = 0; y < 448; ++y) {
        double v = (y + 0.5) / 448;
        double lx = p[0] + (p[6]-p[0])*v, ly = p[1] + (p[7]-p[1])*v;
        double rx = p[2] + (p[4]-p[2])*v, ry = p[3] + (p[5]-p[3])*v;
        for (int x = 0; x < 320; ++x) {
            double u = (x + 0.5) / 320;
            double sx = fmin(width-1, fmax(0, lx+(rx-lx)*u-0.5));
            double sy = fmin(height-1, fmax(0, ly+(ry-ly)*u-0.5));
            int ix = (int)sx, iy = (int)sy;
            int jx = ix+1 < width ? ix+1 : ix, jy = iy+1 < height ? iy+1 : iy;
            double fx = sx-ix, fy = sy-iy;
            double a = gray[iy*width+ix]*(1-fx) + gray[iy*width+jx]*fx;
            double b = gray[jy*width+ix]*(1-fx) + gray[jy*width+jx]*fx;
            grid[y*320+x] = (uint8_t)round(a*(1-fy)+b*fy);
        }
    }
}

static double peakOffset(double before, double peak, double after) {
    double curvature = before - 2 * peak + after;
    return curvature < -1e-8 ? fmax(-0.5, fmin(0.5, 0.5 * (before - after) / curvature)) : 0;
}

double TCSCenteringMatchPatch(const uint8_t *gray, int width, int height,
                             const uint8_t *patch, int x, int y, double *dx, double *dy) {
    const int count = 17 * 17;
    double sum = 0, squares = 0, best = -1;
    for (int k = 0; k < count; ++k) {
        sum += patch[k];
        squares += patch[k] * patch[k];
    }
    double variance = squares - sum * sum / count;
    if (variance < 100 * count) return best;
    double scores[17][17];
    int bestX = 0, bestY = 0;
    for (int j = -8; j <= 8; ++j) for (int i = -8; i <= 8; ++i) {
        scores[j+8][i+8] = -1;
        int left = x + i - 8, top = y + j - 8;
        if (left < 0 || top < 0 || left + 17 > width || top + 17 > height) continue;
        double local = 0, energy = 0, dot = 0;
        for (int row = 0; row < 17; ++row) for (int col = 0; col < 17; ++col) {
            int value = gray[(top + row) * width + left + col];
            local += value;
            energy += value * value;
            dot += value * patch[row * 17 + col];
        }
        double localVariance = energy - local * local / count;
        if (localVariance < 25 * count) continue;
        double score = (dot - sum * local / count) / sqrt(variance * localVariance);
        scores[j+8][i+8] = score;
        if (score > best) { best = score; bestX = i; bestY = j; }
    }
    *dx = bestX;
    *dy = bestY;
    if (best > 0 && abs(bestX) < 8 && abs(bestY) < 8) {
        int i = bestX + 8, j = bestY + 8;
        *dx += peakOffset(scores[j][i-1], best, scores[j][i+1]);
        *dy += peakOffset(scores[j-1][i], best, scores[j+1][i]);
    }
    return best;
}
#endif

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
