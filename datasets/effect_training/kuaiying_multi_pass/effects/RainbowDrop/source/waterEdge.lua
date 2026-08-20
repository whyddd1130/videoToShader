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
uniform sampler2D inputImageTexture;
uniform sampler2D sdfTex;

uniform vec2 screenParams;
uniform float iTime;
#define PI 3.1415926

vec2 lowPrecision(vec4 myuv)
{
    return myuv.xy + myuv.zw / 255.;
}

void main()
{
    float p = 1.0;

    vec4 sdfCol = texture2D(sdfTex, textureCoord);
    vec2 sdfVec = lowPrecision(sdfCol);
    float d = sdfVec.x - sdfVec.y;
    float oriD = d;
    float alpha = smoothstep(-0.2, 0.2, d);
    d += 0.5;

    vec2 uv1 = textureCoord;
    vec2 uv2 = textureCoord;
    float fishEyeRate = mix(4.0, 4.0, smoothstep(0.0, 1.0, iTime)) * p;
    float n = mix(1.0, 1.3, smoothstep(1.0, 1.2 + 0.3 * smoothstep(1.0, 1.777, max(screenParams.x, screenParams.y) / min(screenParams.x, screenParams.y)), iTime)) * (1. - p / 2.);
    float radius = length(uv1 - 0.5);
    float power = PI / n * fishEyeRate / 10.;
    uv1 = normalize(uv1 - 0.5) * tan(radius * power) * n / tan(n * power);
    uv1 += 0.5;
    if (fishEyeRate <= 0.001)
        uv1 = textureCoord;
    float l = d;
    uv1 = mix(uv2, uv1, pow(smoothstep(0., 1., l / .5), 80.0));
    float edgeMask = smoothstep(-0.01, 0.02, oriD);
    uv1 = mix(uv1, textureCoord, edgeMask);
    vec4 col = texture2D(inputImageTexture, uv1);
    gl_FragColor = vec4(col);
}

]]
WaterEdge = class()

function WaterEdge:init()
    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation('position', 0)
    self.program:initWithShaderStrings(vs, fs)
    self.program:bind()
    self.program:sendUniformi('inputImageTexture', 0)
    self.program:sendUniformi('sdfTex', 1)

    local buffer = {}
    glGenBuffers(1,buffer)
    self.vbo = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
end

function WaterEdge:setScreenParams(val1, val2)
    self.program:bind()
    self.program:sendUniformf('screenParams', val1, val2)
end

function WaterEdge:setTime(val1)
    self.program:bind()
    self.program:sendUniformf('iTime', val1)
end

function WaterEdge:draw(texID1, texID2)
    self.program:bind()
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, texID1)
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, texID2)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
end

function WaterEdge:destroy()
    glDeleteBuffers(1, {self.vbo})
end

