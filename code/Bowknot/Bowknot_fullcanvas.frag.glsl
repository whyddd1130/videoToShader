#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;

const float PI = 3.14159265359;
const float TAU = 6.28318530718;
const float INV_SQRT3 = 0.57735026919;

float sourceProgress(float p) {
    p = clamp(p, 0.0, 1.0);
    if (p < 0.097) return mix(0.000, 0.064, p / 0.097);
    if (p < 0.202) return mix(0.064, 0.202, (p - 0.097) / 0.105);
    if (p < 0.298) return mix(0.202, 0.353, (p - 0.202) / 0.096);
    if (p < 0.403) return mix(0.353, 0.403, (p - 0.298) / 0.105);
    if (p < 0.500) return mix(0.403, 0.500, (p - 0.403) / 0.097);
    if (p < 0.597) return mix(0.500, 0.600, (p - 0.500) / 0.097);
    if (p < 0.702) return mix(0.600, 0.647, (p - 0.597) / 0.105);
    if (p < 0.798) return mix(0.647, 0.798, (p - 0.702) / 0.096);
    if (p < 0.903) return mix(0.798, 0.936, (p - 0.798) / 0.105);
    return mix(0.936, 1.000, (p - 0.903) / 0.097);
}

void projectedPoint(float sourceX, float screenY, float rotation,
                    out float sourceY, out float projectedX, out float depth) {
    float sourceU = sourceX * 0.5 + 0.5;
    float localAngle;
    float bendCos;
    float bendSin;
    if (rotation < PI) {
        localAngle = sourceU * rotation;
        bendCos = cos(localAngle);
        bendSin = sin(localAngle);
    } else {
        localAngle = (1.0 - sourceU) * (TAU - rotation);
        bendCos = -cos(localAngle);
        bendSin = sin(localAngle);
    }
    float divisor = bendCos + screenY * INV_SQRT3 * bendSin;
    float safeDivisor = sign(divisor) * max(abs(divisor), 0.00001);
    sourceY = screenY / safeDivisor;
    float perspective = 1.0 - sourceY * INV_SQRT3 * bendSin;
    projectedX = sourceX / perspective;
    depth = sourceY * bendSin;
}

void main() {
    vec2 screen = textureCoord * 2.0 - 1.0;
    float rotation = sourceProgress(uProgress) * TAU;
    float found = 0.0;
    float bestDepth = -1000.0;
    vec2 bestSource = screen;
    float leftX = -1.0;
    float leftY, leftProjectedX, leftDepth;
    projectedPoint(leftX, screen.y, rotation, leftY, leftProjectedX, leftDepth);
    float leftError = leftProjectedX - screen.x;

    for (int segment = 0; segment < 32; ++segment) {
        float rightX = -1.0 + 2.0 * float(segment + 1) / 32.0;
        float rightY, rightProjectedX, rightDepth;
        projectedPoint(rightX, screen.y, rotation, rightY, rightProjectedX, rightDepth);
        float rightError = rightProjectedX - screen.x;
        if (leftError * rightError <= 0.0) {
            float lo = leftX;
            float hi = rightX;
            float flo = leftError;
            for (int refine = 0; refine < 9; ++refine) {
                float mid = 0.5 * (lo + hi);
                float midY, midProjectedX, midDepth;
                projectedPoint(mid, screen.y, rotation, midY, midProjectedX, midDepth);
                float fm = midProjectedX - screen.x;
                if (flo * fm <= 0.0) hi = mid;
                else { lo = mid; flo = fm; }
            }
            float candidateX = 0.5 * (lo + hi);
            float candidateY, candidateProjectedX, candidateDepth;
            projectedPoint(candidateX, screen.y, rotation, candidateY, candidateProjectedX, candidateDepth);
            float valid = step(-1.0, candidateY) * step(candidateY, 1.0) *
                          step(abs(candidateProjectedX - screen.x), 0.01);
            if (valid > 0.5 && (found < 0.5 || candidateDepth > bestDepth)) {
                found = 1.0;
                bestDepth = candidateDepth;
                bestSource = vec2(candidateX, candidateY);
            }
        }
        leftX = rightX;
        leftError = rightError;
    }

    vec3 folded = texture2D(inputImageTexture, clamp(bestSource * 0.5 + 0.5, 0.0, 1.0)).rgb;
    vec3 fallback = texture2D(inputImageTexture, textureCoord).rgb;
    gl_FragColor = vec4(mix(fallback, folded, found), 1.0);
}
