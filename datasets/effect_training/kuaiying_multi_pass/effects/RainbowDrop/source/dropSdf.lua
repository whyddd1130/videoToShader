require('script/RainbowDrop/class')

---@language GLSL
local vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

attribute vec2 position;
varying vec2 textureCoord;

void main()
{
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

---@language GLSL
local fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform vec2 screenParams;
uniform float iTime;

float smin(float a,float b,float k)
{
    float h=clamp((b-a)/k+0.5,0.,1.);
    return mix(b,a,h)-h*(1.-h)*k*.5;   
}
float sdCircle(vec2 p, float r ) 
{
    return length(p)-r;
}
vec4 highPrecision(vec2 myuv)
{
    vec2 newUV = myuv * 255.;
    return vec4(floor(newUV) / 255., fract(newUV));
}

void main()
{
    vec2 newUV = textureCoord - 0.5;
    if(screenParams.x < screenParams.y)
        newUV.y *= screenParams.y / screenParams.x;
    else
        newUV.x *= screenParams.x / screenParams.y;

    float size = iTime * 1.2 - 0.2;
    float angle = atan(newUV.x, newUV.y);
    newUV *= mix(1.0, mix(1.0, .95, smoothstep(0.0, 1.0, iTime)), sin(angle * 5.0 + iTime * 3.2) * 0.5 + 0.5);
    float d = sdCircle(newUV - 0.15 * size * vec2(0., 1.), 0.4 * size);
    float d1 = sdCircle(newUV-0.15*size*vec2(0.951, .31), 0.4 * size);
    float d2 = sdCircle(newUV-0.15*size*vec2(0.589,-0.808),0.4*size);
    float d3 = sdCircle(newUV-0.15*size*vec2(-0.589,-.81),0.4*size);
    float d4 = sdCircle(newUV-0.15*size*vec2(-952,.307),0.4*size);
    d=smin(d,d2,0.35);
    d=smin(d,d1,0.35);
    d=smin(d,d3,0.35);
    d=smin(d,d4,0.35);

    vec2 sdfVec = vec2(clamp(d,0.0,1.0),clamp(-d,0.0,1.0));
    gl_FragColor = vec4(highPrecision(sdfVec));
}

]]
DropSdf = class()

function DropSdf:init()
    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation('position', 0)
    self.program:initWithShaderStrings(vs, fs)
    self.program:bind()

    local buffer = {}
    glGenBuffers(1,buffer)
    self.vbo = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
end

function DropSdf:setScreenParams(val1, val2)
    self.program:bind()
    self.program:sendUniformf('screenParams', val1, val2)
end

function DropSdf:setTime(val1)
    self.program:bind()
    self.program:sendUniformf('iTime', val1)
end

function DropSdf:draw(texID)
    self.program:bind()
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
end

function DropSdf:destroy()
    glDeleteBuffers(1, {self.vbo})
end

