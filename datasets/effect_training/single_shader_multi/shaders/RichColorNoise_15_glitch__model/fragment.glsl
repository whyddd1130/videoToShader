precision highp float;


uniform float uProgress;
uniform float uTime;
uniform sampler2D inputImageTexture;

varying vec2 uv;
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
#define glithIns (0.2 + 1.2 * uProgress)
#define blurSize (1.0 + 34.0 * uProgress)
void main()
{
    vec2 mySize = u_ScreenParams.xy/min(u_ScreenParams.x,u_ScreenParams.y)*720.;
    vec2 offset = vec2(0.6)/mySize;

    vec2 myuv = vec2(uv.x,uv.y);
    vec4 col = texture2D(inputImageTexture,myuv);
    vec4 oriCol = col;
    col.r = texture2D(inputImageTexture,myuv+glithIns*offset*vec2(2,2)).r;
    col.g = texture2D(inputImageTexture,myuv+glithIns*offset*vec2(2,0)).g;
    col.b = texture2D(inputImageTexture,myuv+glithIns*offset*vec2(-2,0.6)).b;
    // blendColor.r = texture2D(inputImageTexture, uv + vec2(rx / float(imageWidth), ry/float(imageHeight))).r;
    // blendColor.g = texture2D(inputImageTexture, uv + vec2(gx / float(imageWidth), gy/float(imageHeight))).g;
    // blendColor.b = texture2D(inputImageTexture, uv + vec2(bx / float(imageWidth), by/float(imageHeight))).b;
    // col.b = texture2D(inputImageTexture,myuv+offset).b;

    gl_FragColor = vec4(mix(vec3(0.5),(col.rgb-oriCol.rgb)*0.5+0.5,1.0),1.0);
}
