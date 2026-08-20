#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif// GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float edgeThreshold;
uniform float edgeSoftness;
uniform float edgeOpacity;
uniform float edgeContrast;

uniform vec2 samplerSteps;
uniform float edgeWidth;
uniform int renderType;

float getAve(vec2 uv)
{
    vec3 rgb = texture2D(inputImageTexture, uv).rgb;
    vec3 lum = vec3(0.299, 0.587, 0.114);
    return dot(lum, rgb);
}

// Detect edge
vec4 sobel(vec2 uv, vec2 dir)
{
    float np = getAve(uv + (vec2(-1.0, 1.0) + dir ) * samplerSteps * edgeWidth);
    float zp = getAve(uv + (vec2( 0.0, 1.0) + dir ) * samplerSteps * edgeWidth);
    float pp = getAve(uv + (vec2(1.0, 1.0) + dir ) * samplerSteps * edgeWidth);
    
    float nz = getAve(uv + (vec2(-1.0, 0.0) + dir ) * samplerSteps * edgeWidth);
    float pz = getAve(uv + (vec2(1.0, 0.0) + dir ) * samplerSteps * edgeWidth);
    
    float nn = getAve(uv + (vec2(-1.0, -1.0) + dir ) * samplerSteps * edgeWidth);
    float zn = getAve(uv + (vec2( 0.0, -1.0) + dir ) * samplerSteps * edgeWidth);
    float pn = getAve(uv + (vec2(1.0, -1.0) + dir ) * samplerSteps * edgeWidth);
    
    float gx = (np * -3. + nz * -10. + nn * -3. + pp * 3. + pz * 10. + pn * 3.);
    float gy = (np * -3. + zp * -10. + pp * -3. + nn * 3. + zn * 10. + pn * 3.);
    
    vec2 G = vec2(gx, gy);
    float grad = length(G);
    float angle = atan(G.y, G.x);
    return vec4(G, grad, angle);
}

// Make edge thinner
vec2 hysteresisThr(vec2 uv, float mn, float mx)
{
    vec4 edge = sobel(uv, vec2(0.0));
    vec2 dir = vec2(cos(edge.w), sin(edge.w));
    dir *= vec2(-1.0, 1.0); // rotate 90 degrees.
    
    vec4 edgep = sobel(uv, dir);
    vec4 edgen = sobel(uv, -dir);
    if(edge.z < edgep.z || edge.z < edgen.z) edge.z = 0.;
    
    return vec2((edge.z > mn) ? edge.z : 0., (edge.z > mx) ? edge.z : 0.);
}

float cannyEdge(vec2 uv, float mn, float mx)
{
    vec2 np = hysteresisThr(uv + vec2(-1.0, 1.0) * samplerSteps, mn, mx);
    vec2 zp = hysteresisThr(uv + vec2( 0.0, 1.0) * samplerSteps, mn, mx);
    vec2 pp = hysteresisThr(uv + vec2(1.0, 1.0) * samplerSteps, mn, mx);
    
    vec2 nz = hysteresisThr(uv + vec2(-1.0, 0.0) * samplerSteps, mn, mx);
    vec2 zz = hysteresisThr(uv + vec2( 0.0, 0.0) * samplerSteps, mn, mx);
    vec2 pz = hysteresisThr(uv + vec2(1.0, 0.0) * samplerSteps, mn, mx);
    
    vec2 nn = hysteresisThr(uv + vec2(-1.0, -1.0) * samplerSteps, mn, mx);
    vec2 zn = hysteresisThr(uv + vec2( 0.0, -1.0) * samplerSteps, mn, mx);
    vec2 pn = hysteresisThr(uv + vec2(1.0, -1.0) * samplerSteps, mn, mx);
    
    return min(1., step(1e-2, zz.x*8.) * smoothstep(.0, .3, np.y + zp.y + pp.y + nz.y + pz.y + nn.y + zn.y + pn.y)*8.);
}

void main() 
{
    float edge = cannyEdge(textureCoord, 0.0, edgeThreshold); 
    if(renderType == 2)
    {
        vec4 col = mix(vec4(1.0), vec4(0.0, 0.0, 0.0, 1.0), edge * edgeOpacity); 
        gl_FragColor = col;
    }
    if(renderType == 3)
    {
        vec4 originColor = texture2D(inputImageTexture, textureCoord);
        vec4 c1 = originColor * (1.0 - edge * edgeOpacity);
        vec4 c2 = vec4(0.0, 0.0, 0.0, 1.0) * edge * edgeOpacity;
        gl_FragColor = c1 + c2;
    }
}
