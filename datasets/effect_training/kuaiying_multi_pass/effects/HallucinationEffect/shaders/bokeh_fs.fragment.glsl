#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float u_baseTexWidth;
uniform float u_baseTexHeight;
uniform float u_blurSize;
uniform float u_lightIns;
uniform float u_intensity;
uniform float u_regionIns;
uniform float u_quality;
uniform float u_scaleX;
uniform float u_scaleY;

mat2 rotate2d(in float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c);
}

float sdf(vec2 uv)
{
    vec2 newUV = uv;

    return step(dot(newUV, newUV), 121.);
}
vec2 flipUV(vec2 uv)
{
    return abs(mod(uv + 1., 2.) - 1.0);
}

vec4 blur(sampler2D inputTexture, vec2 textureCoordinate, float blurSize, vec2 screenSize)
{
    if (u_intensity < 0.01) {
        return texture2D(inputTexture, textureCoordinate);
    }
    float amount = 539.45;
    vec4 oriCol = vec4(0.);
    vec4 maxCol = oriCol;
    vec4 bokeh = pow(oriCol, vec4(9.0)) * amount + .4;
    vec4 sumCol = vec4(0.);
    vec4 sumWeight = bokeh;
    vec2 unitUV = vec2(2., 2.) * vec2(u_scaleX, u_scaleY) * vec2(blurSize) / screenSize;

    float blurStep = mix(2.0, 0.5, u_intensity) * mix(2., 1.0, u_quality);
    float blurRadius = 12. / blurStep * mix(0.6, 1.0, u_quality);
    blurRadius = max(5., blurRadius);
    float maxRegionIns = mix(0.7, 1.0, u_regionIns);
    for (float i = 0.; i < 30.; i++) {
        if (i > blurRadius || u_intensity < 0.3) {
            break;
        }
        for (float j = 0.; j < 30.; j++) {
            if (j > blurRadius) {
                break;
            }
            vec2 tempVec = vec2(mix(-11., 11., i / blurRadius), mix(-11., 11., j / blurRadius));
            if (sdf(tempVec) < 0.5) {
                continue;
            }
            vec4 tempCol = texture2D(inputTexture, (textureCoordinate - 0.5 * tempVec * unitUV));
            maxCol = max(maxCol, tempCol * maxRegionIns);
            bokeh = pow(tempCol, vec4(9.0)) * amount + .4;
            bokeh *= u_regionIns;
            sumCol += bokeh * tempCol;
            sumWeight += bokeh;
        }
    }

    float circleRadius = 34. / blurStep * mix(0.5, 1.0, clamp(u_quality * 1.5, 0.0 ,1.0));
    circleRadius = max(15.,circleRadius);
    mat2 rotmat = rotate2d(6.28 / circleRadius);
    vec2 tempVec = vec2(11, 0);
    for (float i = 0.; i < 70.; i++) {
        if (i > circleRadius) {
            break;
        }
        tempVec *= rotmat;
        vec4 tempCol = texture2D(inputTexture, (textureCoordinate - 0.5 * tempVec * unitUV));
        maxCol = max(maxCol, tempCol);
        bokeh = pow(tempCol, vec4(9.0)) * amount + .4;
        sumCol += bokeh * tempCol;
        sumWeight += bokeh;
    }

    vec4 resultCol = clamp(sumCol / sumWeight, 0., 1.);
    return vec4(mix(resultCol, maxCol, clamp(resultCol * u_lightIns, 0.0, 1.0)));
}

void main()
{
    vec2 screenSize = vec2(u_baseTexWidth, u_baseTexHeight) / min(u_baseTexWidth, u_baseTexHeight) * 720.;
    gl_FragColor = blur(inputImageTexture, textureCoord, u_blurSize, screenSize);
}
