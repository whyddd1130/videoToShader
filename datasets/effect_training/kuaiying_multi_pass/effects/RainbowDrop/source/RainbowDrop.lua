require('script/RainbowDrop/waterEdge')
require('script/RainbowDrop/dropSdf')
require('script/RainbowDrop/rainbowBlend')

local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

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

void main() 
{
    gl_FragColor = texture2D(inputImageTexture, textureCoord);
}
]]

---@language GLSL
local blurX_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform sampler2D sdfTexture;

uniform vec2 screenParams;
uniform float iTime;
uniform float blurSize;

vec2 lowPrecision(vec4 myuv)
{
    return myuv.xy + myuv.zw / 255.;
}

void main()
{
    float half_gaussian_weight[9];
    half_gaussian_weight[0] = 0.20;
    half_gaussian_weight[1] = 0.19;
    half_gaussian_weight[2] = 0.17;
    half_gaussian_weight[3] = 0.15;
    half_gaussian_weight[4] = 0.13;
    half_gaussian_weight[5] = 0.11;
    half_gaussian_weight[6] = 0.08;
    half_gaussian_weight[7] = 0.05;
    half_gaussian_weight[8] = 0.02;
    
    float ratioFlag = smoothstep(1.0,1.777,max(screenParams.x,screenParams.y)/min(screenParams.x,screenParams.y));
    vec2 uv1 = (textureCoord-0.5)*mix(1.0,0.76,smoothstep(0.0,0.2,iTime)*smoothstep(1.2+0.3*ratioFlag,0.2,iTime))+0.5;
    vec4 col = texture2D(inputImageTexture, uv1)*half_gaussian_weight[0];
    float num = half_gaussian_weight[0];

    vec4 sdfCol = texture2D(sdfTexture,textureCoord);
    vec2 sdfVec = lowPrecision(sdfCol);
    float d = sdfVec.x-sdfVec.y;
    vec2 offset = vec2(blurSize,0.0)/screenParams.xy*smoothstep(-0.03,0.03,d);

    for(int i= 1;i<=8;i++)
    {
        float j = float(i);
        vec2 tempUV = uv1-offset*j;
        vec4 res_r = texture2D(inputImageTexture, tempUV);
        col+=res_r*half_gaussian_weight[i];
        tempUV = uv1+offset*j;
        res_r = texture2D(inputImageTexture, tempUV);
        col+=res_r*half_gaussian_weight[i];
        num+=2.0*half_gaussian_weight[i];
    }
    col /= num;
    col.rgb *= mix(0.8, 1.0, smoothstep(0.0, 1.0, iTime));
    gl_FragColor = col;
}
]]

---@language GLSL
local blurY_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform sampler2D sdfTexture;

uniform vec2 screenParams;
uniform float iTime;
uniform float blurSize;

vec2 lowPrecision(vec4 myuv)
{
    return myuv.xy+myuv.zw/255.;
}
void main()
{
    float half_gaussian_weight[9];
    
    half_gaussian_weight[0]= 0.20;//0.137401;
    half_gaussian_weight[1]= 0.19;//0.125794;
    half_gaussian_weight[2]= 0.17;//0.106483;
    half_gaussian_weight[3]= 0.15;//0.080657;
    half_gaussian_weight[4]= 0.13;//0.054670;
    half_gaussian_weight[5]= 0.11;//0.033159;
    half_gaussian_weight[6]= 0.08;//0.017997;
    half_gaussian_weight[7]= 0.05;//0.008741;
    half_gaussian_weight[8]= 0.02;//0.003799;

    vec2 uv1 = textureCoord;
    vec4 col = texture2D(inputImageTexture, textureCoord) * half_gaussian_weight[0];
    float num = half_gaussian_weight[0];

    vec4 sdfCol = texture2D(sdfTexture,textureCoord);
    vec2 sdfVec = lowPrecision(sdfCol);
    float d = sdfVec.x-sdfVec.y;
    vec2 offset = vec2(0.0,blurSize)/screenParams.xy*smoothstep(-0.03, 0.03, d);

    for(int i= 1;i<=8;i++)
    {
        float j = float(i);
        vec2 tempUV = uv1-offset*j;
        vec4 res_r = texture2D(inputImageTexture, tempUV);
        col+=res_r*half_gaussian_weight[i];
        tempUV = uv1+offset*j;
        res_r = texture2D(inputImageTexture, tempUV);
        col+=res_r*half_gaussian_weight[i];
        num+=2.0*half_gaussian_weight[i];
    }
    col/=num;
    col.rgb*=mix(0.8,1.0,smoothstep(0.0,1.0,iTime));
    gl_FragColor = col;
}
]]

---@language GLSL
local blur_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float blurSize;

void main()
{
    vec2 uv1 = textureCoord;
    vec4 col = vec4(0.0);
    float num = 0.0;
    for (int i = 1; i <= 8; i++)
    {
        float j = float(i);
        vec2 tempUV = (uv1 - 0.5) / mix(1.0, blurSize, j / 8.) + 0.5;
        vec4 res_r = texture2D(inputImageTexture, tempUV);
        col += res_r;
        tempUV = (uv1 - 0.5) * mix(1.0, blurSize, j / 8.) + 0.5;
        res_r = texture2D(inputImageTexture, tempUV);
        col += res_r;
        num += 2.0;
    }
    col /= num;
    gl_FragColor = col;
}
]]

---@language GLSL
local blurAngle_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 screenParams;

mat2 rot2(float angle)
{
    float sinA = sin(angle);
    float cosA = cos(angle);
    return mat2(cosA, -sinA,
                sinA, cosA);
}
vec2 rotUV(vec2 oriUV, mat2 rotAngleMat)
{
    vec2 temp = oriUV - 0.5;
    temp.x *= screenParams.x / screenParams.y;
    temp = temp * rotAngleMat;
    temp.x /= screenParams.x / screenParams.y;
    return temp + 0.5;
    return oriUV;
}

void main()
{
    vec4 col = texture2D(inputImageTexture, textureCoord);
    float num = 1.0;
    float normalAngle = 0.05 * 0.04;
    mat2 rightAngleMat = rot2(normalAngle);
    mat2 leftAngleMat = rot2(-normalAngle);
    vec2 rightUV = textureCoord;
    vec2 leftUV = textureCoord;
    for (int i = 1; i <= 8; i++)
    {
        float j = float(i);
        rightUV = rotUV(rightUV, rightAngleMat);
        vec4 res_r = texture2D(inputImageTexture, rightUV);
        col += res_r;
        leftUV = rotUV(leftUV, leftAngleMat);
        res_r = texture2D(inputImageTexture, leftUV);
        col += res_r;
        num += 2.0;
    }
    col /= num;
    gl_FragColor = col;
}
]]

RainbowDrop = {}

function RainbowDrop:matchWithId(effectId)
    return 'KFM KSkr RainbowDrop' == effectId
end

function RainbowDrop.createWithId(effectId)
    if not RainbowDrop:matchWithId(effectId) then
        return nil
    end
    local o = {
        dropSdfDraw = {},
        blurXProgram = {},
        blurYProgram = {},
        blurProgram = {},
        blurAngleProgram = {},
        waterEdgeDraw = {},
        rainbowBlendDraw = {},
        color = 0.0,
        luminance = 0.0,
        speed = 0.0,
        currentWidth = 0,
        currentHeight = 0,
        currentTime = 0.0,
        blurSize = 0.0
    }
    o = newObject(o, RainbowDrop)
    o:init()
    return o;
end

function RainbowDrop:init()
    self.dropSdfDraw = DropSdf()

    self.blurXProgram = CGE.ProgramObject()
    self.blurXProgram:bindAttribLocation('position', 0)
    self.blurXProgram:initWithShaderStrings(vs, blurX_fs)
    self.blurXProgram:bind()
    self.blurXProgram:sendUniformi('inputImageTexture', 0)
    self.blurXProgram:sendUniformi('sdfTexture', 1)

    self.blurYProgram = CGE.ProgramObject()
    self.blurYProgram:bindAttribLocation('position', 0)
    self.blurYProgram:initWithShaderStrings(vs, blurY_fs)
    self.blurYProgram:bind()
    self.blurYProgram:sendUniformi('inputImageTexture', 0)
    self.blurYProgram:sendUniformi('sdfTexture', 1)

    self.blurProgram = CGE.ProgramObject()
    self.blurProgram:bindAttribLocation('position', 0)
    self.blurProgram:initWithShaderStrings(vs, blur_fs)
    self.blurProgram:bind()
    self.blurProgram:sendUniformi('inputImageTexture', 0)

    self.blurAngleProgram = CGE.ProgramObject()
    self.blurAngleProgram:bindAttribLocation('position', 0)
    self.blurAngleProgram:initWithShaderStrings(vs, blurAngle_fs)
    self.blurAngleProgram:bind()
    self.blurAngleProgram:sendUniformi('inputImageTexture', 0)

    self.waterEdgeDraw = WaterEdge()

    self.rainbowBlendDraw = RainbowBlend()

    local buffer = {}
    glGenBuffers(1,buffer)
    self.vbo = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
end

function RainbowDrop:remap(x, a, b)
    return x * (b - a) + a
end

function RainbowDrop:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- Color
        self.color = self:remap(val1 / 100.0, 0, 1)
    elseif index == 2 then
        -- Luminance
        self.luminance = self:remap(val1 / 100.0, 0, 1)
    elseif index == 3 then
        -- Speed
        self.speed = val1 / 100.0 * 1.5 + 0.5
    elseif index == 4 then
        -- Speed
        self.blurSize = val1 / 10.0
    end
end

function RainbowDrop:resize(width, height)

end

function RainbowDrop:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height

    self.dropSdfDraw:setScreenParams(width, height)

    self.blurXProgram:bind()
    self.blurXProgram:sendUniformf('screenParams', width, height)
    self.blurYProgram:bind()
    self.blurYProgram:sendUniformf('screenParams', width, height)
    self.blurAngleProgram:bind()
    self.blurAngleProgram:sendUniformf('screenParams', width, height)

    self.waterEdgeDraw:setScreenParams(width, height)
    self.rainbowBlendDraw:setScreenParams(width, height)
end

function RainbowDrop:updateTimeAndFrame(time, frame)
    self.currentTime = time
end

function RainbowDrop:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    local fbo1 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo1:bind()
    self.dropSdfDraw:setTime(self.speed * self.currentTime)
    self.dropSdfDraw:draw(inputTex)

    local fbo2 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo2:bind()
    self.blurXProgram:bind()
    self.blurXProgram:sendUniformf('iTime', self.speed * self.currentTime)
    self.blurXProgram:sendUniformf('blurSize', self.blurSize)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local fbo3 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo3:bind()
    self.blurYProgram:bind()
    self.blurYProgram:sendUniformf('iTime', self.speed * self.currentTime)
    self.blurYProgram:sendUniformf('blurSize', self.blurSize)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    fbo2:bind()
    self.blurProgram:bind()
    self.blurProgram:sendUniformf('blurSize', 1.15)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo3:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local fbo5 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo5:bind()
    self.blurProgram:bind()
    self.blurProgram:sendUniformf('blurSize', 1.2)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    fbo2:bind()
    self.blurAngleProgram:bind()
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo5:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    fbo5:bind()
    self.waterEdgeDraw:setTime(self.speed * self.currentTime)
    self.waterEdgeDraw:draw(fbo2:texId(), fbo1:texId())

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.rainbowBlendDraw:setTime(self.speed * self.currentTime)
    self.rainbowBlendDraw:setColor(self.color)
    self.rainbowBlendDraw:setAlpha(self.luminance)
    self.rainbowBlendDraw:draw(fbo5:texId(), fbo1:texId(), fbo3:texId())

    AESP:recycleCachedFrameBuffer(fbo1)
    AESP:recycleCachedFrameBuffer(fbo2)
    AESP:recycleCachedFrameBuffer(fbo3)
    AESP:recycleCachedFrameBuffer(fbo5)
end

function RainbowDrop:onDestroy()
    self.waterEdgeDraw:destroy()
    self.dropSdfDraw:destroy()
    self.rainbowBlendDraw:destroy()
end
    