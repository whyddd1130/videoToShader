#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D frontTex;
uniform sampler2D backTex;

const float PI = 3.1415926;

float cut(vec2 u) {return step(0.,u.x)*step(u.x,1.)*step(0.,u.y)*step(u.y,1.);}
vec2 mirror(vec2 x) { return abs(mod(x+1., 2.)-1.); }

void ExposureLighten(vec4 i_col, float _alpha, out vec4 o_col){

    o_col = pow(i_col, 1./vec4(2.2)) * pow(0.75, -1.0);
    o_col += 1.0;
    o_col = pow(o_col, vec4(1.0));
    o_col = mix(i_col, o_col, _alpha);
    o_col = pow(o_col, vec4(2.2));
}

void main()
{
    vec2 uv1 = textureCoord;
    vec4 frontCol = texture2D(frontTex, mirror(uv1));
    vec2 uv2 = textureCoord;
    uv2 -= 0.5;
    uv2 += 0.5;
    vec4 backCol = texture2D(backTex, uv2) * cut(uv2);
    vec4 res = backCol;
    res = mix(frontCol, backCol, res.a);    
    gl_FragColor = res;
}
