#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

attribute vec2 position;
uniform float uTime;
uniform float uProgress;
varying vec2 textureCoord;
varying float vDepth;
varying float vFace;

// The platform supplies only a fullscreen quad.  We embed the quad as a
// textured card in camera space and rotate it around its vertical axis.
// This is genuine perspective interpolation on one plane ("2.5D"), not a
// displacement-map warp.
void main() {
    textureCoord = position * 0.5 + 0.5;

    // One complete 360-degree card turn during the exported clip. uProgress
    // is the renderer's normalized timeline.
    float t = clamp(uProgress, 0.0, 1.0);
    float ease = t * t * (3.0 - 2.0 * t);
    float angle = 6.28318530718 * ease;
    float c = cos(angle);
    float s = sin(angle);
    // Positive: front side. Negative: back side. This is passed explicitly
    // instead of relying on driver-specific face culling state.
    vFace = c;
    vec3 p = vec3(position.x, position.y, 0.0);
    p = vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);

    // Move the card away from the camera and project it. Keeping w separate
    // gives the texture coordinates perspective-correct interpolation.
    float cameraDistance = 2.15;
    float w = cameraDistance - p.z;
    vDepth = w;
    float sway = 0.07 * sin(uTime * 1.1);
    gl_Position = vec4(p.x * 1.52 + sway * w, p.y * 1.52, p.z, w);
}
