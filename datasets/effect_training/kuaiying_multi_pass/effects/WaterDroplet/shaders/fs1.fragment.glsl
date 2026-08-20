#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float chromatic_red;
uniform float chromatic_blue;

vec2 Mirror(vec2 x) { return abs(mod(x-1., 2.)-1.); }
float cut(vec2 u) { return step(0., u.x)*step(u.x, 1.)*step(0., u.y)*step(u.y, 1.); }

void main()
{
    vec2 uv1 = textureCoord;
    uv1 -= 0.5;
    uv1 += 0.5;
    vec4 col_r = texture2D(inputImageTexture, Mirror(vec2(uv1.x + chromatic_red, uv1.y)));
    vec4 col_g = texture2D(inputImageTexture, Mirror(vec2(uv1.x, uv1.y)));
    vec4 col_b = texture2D(inputImageTexture, Mirror(vec2(uv1.x - chromatic_blue, uv1.y)));

    vec4 res = vec4(col_r.r, col_g.g, col_b.b, max(col_r.a + col_g.a + col_b.a, 1.));
    gl_FragColor = res;
}
