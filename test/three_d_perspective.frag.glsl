#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;
varying vec2 textureCoord;
varying float vDepth;
varying float vFace;

void main() {
    // Texture coordinates are perspective-correct because the vertex shader
    // emits a non-constant clip-space w.  Add a restrained travelling light
    // and edge falloff, so the rotation reads as a spatial card rather than
    // merely a scaled 2D image.
    // The reverse side is deliberately a horizontal mirror of the source
    // image, so the card stays visually populated after it turns past 90°.
    vec2 sampleUv = textureCoord;
    if (vFace < 0.0) {
        sampleUv.x = 1.0 - sampleUv.x;
    }
    vec4 color = texture2D(inputImageTexture, sampleUv);
    float depthShade = clamp(1.38 - 0.23 * vDepth, 0.62, 1.0);
    float lightSweep = 0.90 + 0.16 * sin((textureCoord.x - 0.5) * 4.5 - uTime * 1.1);
    float edge = smoothstep(0.0, 0.12, textureCoord.x)
               * smoothstep(0.0, 0.12, 1.0 - textureCoord.x);
    float vignette = 1.0 - 0.13 * dot(textureCoord - 0.5, textureCoord - 0.5);
    float backSideShade = vFace < 0.0 ? 0.82 : 1.0;
    color.rgb *= depthShade * lightSweep * mix(0.74, 1.0, edge) * vignette * backSideShade;
    gl_FragColor = color;
}
