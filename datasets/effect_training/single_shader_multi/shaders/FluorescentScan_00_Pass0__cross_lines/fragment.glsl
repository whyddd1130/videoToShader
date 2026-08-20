precision highp float;

uniform float uProgress;
uniform float uTime;
varying vec2 uv0;

uniform sampler2D inputImageTexture;
#define amount (0.2 + 3.0 * uProgress)
#define range 1.0
#define passthrough 0.0
#define width vec2(1.0, 1.0)
#define imageHeight 1080
#define imageWidth 1080
#define intensity (0.2 + 2.5 * uProgress)
vec4 edges()
{
    vec2 vUv=uv0;
    vec2 texel= width / vec2(imageWidth,imageHeight);
    mat3 G[2];
    const mat3 g0=mat3(1.,2.,1.,0.,0.,0.,-1.,-2.,-1.);
    const mat3 g1=mat3(1.,0.,-1.,2.,0.,-2.,1.,0.,-1.);

    mat3 I;
    float cnv[2];
    vec3 sample;
    G[0]=g0;
    G[1]=g1;
    for(float i=0.;i<3.;i++){
        for(float j=0.;j<3.;j++){
            sample=texture2D(inputImageTexture,vUv+texel*vec2(i-1.,j-1.)).rgb;
            I[int(i)][int(j)]=length(sample);
        }
    }
    for(int i=0;i<2;i++){
        float dp3=dot(G[i][0],I[0])+dot(G[i][1],I[1])+dot(G[i][2],I[2]);
        cnv[i]=dp3*dp3;
    }
    vec4 orig=texture2D(inputImageTexture,vUv);
    vec4 resultColor=orig*passthrough+vec4(.5*sqrt(cnv[0]*cnv[0]+cnv[1]*cnv[1]))*amount;
    resultColor.rgb *= (intensity + 0.01);
    resultColor.a = 1.0;
    return resultColor;
}


void main(void)
{
    vec4 resultColor=edges();

    resultColor.a = 1.0;
    gl_FragColor=resultColor;
}
