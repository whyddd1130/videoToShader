
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
local circle_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_ScreenParams;
uniform vec2 u_center;
uniform float u_maxDistance;
uniform float u_smoothDistance;
uniform float u_circleWidth;
uniform float u_circleDisWidthChange;
uniform float u_circleDisSmoothChange;
uniform float u_nowRadius;
uniform float u_nowRadius1;
uniform float u_mask;

float normpdf(in float x, in float sigma)
{
    return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}
vec4 enCode(float a)
{
    float a1 = floor(a*255.);
    float b1 = fract(a*255.);
    float a2 = floor(b1*255.);
    float b2 = fract(b1*255.);
    float a3 = floor(b2*255.);
    float b3 = fract(b2*255.);
    return vec4(a1/255.,a2/255.,a3/255.,b3);
}
void main()
{
    vec2 ratio = u_ScreenParams.xy / min(u_ScreenParams.x, u_ScreenParams.y);
    vec2 uv0 = textureCoord - u_center;
    uv0 *= ratio;
    float nowLen = length(uv0);
    float nowRadius = u_nowRadius;
    float nowWidth = u_circleWidth*(1.+(nowRadius)/(2.*u_maxDistance)*u_circleDisWidthChange);
    float nowSmoothDistance = max(0.,u_smoothDistance*(2.-(nowRadius)/(2.*u_maxDistance)*u_circleDisSmoothChange));
    float mask = smoothstep(nowRadius-nowSmoothDistance, nowRadius, nowLen) * (1.-smoothstep(nowRadius+nowWidth, nowRadius+nowWidth+nowSmoothDistance, nowLen));
    
    nowRadius = u_nowRadius1;
    nowWidth = u_circleWidth*(1.+(nowRadius)/(2.*u_maxDistance)*u_circleDisWidthChange);
    nowSmoothDistance = max(0.,u_smoothDistance*(2.-(nowRadius)/(2.*u_maxDistance)*u_circleDisSmoothChange));
    mask += smoothstep(nowRadius-nowSmoothDistance, nowRadius, nowLen) * (1.-smoothstep(nowRadius+nowWidth, nowRadius+nowWidth+nowSmoothDistance, nowLen));
    mask *= min(smoothstep(0., u_maxDistance, nowLen)+0.5,1.0);
    gl_FragColor = vec4(enCode(mask*u_mask));
}
]]

---@language GLSL
local blurX0_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_ScreenParams;
uniform float blurSize;

float normpdf(in float x, in float sigma)
{
    return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}
vec4 enCode(float a){
    float a1 = floor(a*255.);
    float b1 = fract(a*255.);
    float a2 = floor(b1*255.);
    float b2 = fract(b1*255.);
    float a3 = floor(b2*255.);
    float b3 = fract(b2*255.);
    return vec4(a1/255.,a2/255.,a3/255.,b3);
}
float deCode(vec4 a){
    return a.x+a.y/255.+a.z/(255.*255.)+a.w/(255.*255.*255.);
}
void main()
{
    vec2 offset = vec2(1.0, 0.0)*vec2(blurSize)/u_ScreenParams.xy;

    float weight0 = normpdf(0.0,25.);
    float resultGray = deCode(texture2D(inputImageTexture, textureCoord))*weight0;
    float num = weight0;
    for(int i = 1; i <= 50; i++){
        float j = float(i);
        float tempWeight = normpdf(j,25.);
        resultGray+=deCode(texture2D(inputImageTexture, textureCoord + j*offset))*tempWeight;
        resultGray+=deCode(texture2D(inputImageTexture, textureCoord - j*offset))*tempWeight;
        num+=2.0*tempWeight;
    }
    resultGray/=num;
    gl_FragColor = vec4(enCode(resultGray));
}
]]

---@language GLSL
local blurY0_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_ScreenParams;
uniform float blurSize;

float normpdf(in float x, in float sigma)
{
    return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}
vec4 enCode(float a){
    float a1 = floor(a*255.);
    float b1 = fract(a*255.);
    float a2 = floor(b1*255.);
    float b2 = fract(b1*255.);
    float a3 = floor(b2*255.);
    float b3 = fract(b2*255.);
    return vec4(a1/255.,a2/255.,a3/255.,b3);
}
float deCode(vec4 a){
    return a.x+a.y/255.+a.z/(255.*255.)+a.w/(255.*255.*255.);
}
void main()
{
    vec2 offset = vec2(0.0, 1.0)*vec2(blurSize)/u_ScreenParams.xy;

    float weight0 = normpdf(0.0,25.);
    float resultGray = deCode(texture2D(inputImageTexture, textureCoord))*weight0;
    float num = weight0;
    for(int i = 1 ;i <= 50 ;i++){
        float j = float(i);
        float tempWeight = normpdf(j,25.);
        resultGray+=deCode(texture2D(inputImageTexture, textureCoord + j*offset))*tempWeight;
        resultGray+=deCode(texture2D(inputImageTexture, textureCoord - j*offset))*tempWeight;
        num+=2.0*tempWeight;
    }
    resultGray/=num;
    gl_FragColor = vec4(enCode(resultGray));
}
]]

---@language GLSL
local blurX1_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_ScreenParams;
uniform float blurSize;

float normpdf(in float x, in float sigma)
{
    return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}
vec4 enCode(float a){
    float a1 = floor(a*255.);
    float b1 = fract(a*255.);
    float a2 = floor(b1*255.);
    float b2 = fract(b1*255.);
    float a3 = floor(b2*255.);
    float b3 = fract(b2*255.);
    return vec4(a1/255.,a2/255.,a3/255.,b3);
}
float deCode(vec4 a){
    return a.x+a.y/255.+a.z/(255.*255.)+a.w/(255.*255.*255.);
}
void main()
{
    vec2 offset = vec2(1.0,0.0)*vec2(blurSize)/u_ScreenParams.xy;

    float weight0 = normpdf(0.0,5.);
    float resultGray = deCode(texture2D(inputImageTexture, textureCoord))*weight0;
    float num = weight0;
    for(int i = 1 ;i <= 5 ;i++){
        float j = float(i);
        float tempWeight = normpdf(j,5.);
        resultGray+=deCode(texture2D(inputImageTexture, textureCoord+j*offset))*tempWeight;
        resultGray+=deCode(texture2D(inputImageTexture, textureCoord-j*offset))*tempWeight;
        num+=2.0*tempWeight;
    }
    resultGray/=num;
    gl_FragColor = vec4(enCode(resultGray));
}
]]

---@language GLSL
local blurY1_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_ScreenParams;
uniform float blurSize;

float normpdf(in float x, in float sigma)
{
    return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}
vec4 enCode(float a){
    float a1 = floor(a*255.);
    float b1 = fract(a*255.);
    float a2 = floor(b1*255.);
    float b2 = fract(b1*255.);
    float a3 = floor(b2*255.);
    float b3 = fract(b2*255.);
    return vec4(a1/255.,a2/255.,a3/255.,b3);
}
float deCode(vec4 a){
    return a.x+a.y/255.+a.z/(255.*255.)+a.w/(255.*255.*255.);
}
void main()
{
    vec2 offset = vec2(0.0,1.0)*vec2(blurSize)/u_ScreenParams.xy;

    float weight0 = normpdf(0.0,5.);
    float resultGray = deCode(texture2D(inputImageTexture, textureCoord))*weight0;
    float num = weight0;
    for(int i = 1 ;i <= 5 ;i++){
        float j = float(i);
        float tempWeight = normpdf(j,5.);
        resultGray+=deCode(texture2D(inputImageTexture, textureCoord+j*offset))*tempWeight;
        resultGray+=deCode(texture2D(inputImageTexture, textureCoord-j*offset))*tempWeight;
        num+=2.0*tempWeight;
    }
    resultGray/=num;
    gl_FragColor = vec4(enCode(resultGray));
}
]]

---@language GLSL
local water_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform sampler2D sdfImageTexture;

uniform vec2 u_ScreenParams;
uniform float waterIns;
uniform float stepIns;

float deCode(vec4 a){
    return a.x+a.y/255.+a.z/(255.*255.)+a.w/(255.*255.*255.);
}
float mirror(float x){
    return abs(mod(x-1.0,2.0)-1.0);
}
vec2 mirror(vec2 uv){
    return vec2(mirror(uv.x),mirror(uv.y));
}
vec4 getCol(vec2 uv){
    vec2 mySize = u_ScreenParams.xy/min(u_ScreenParams.x,u_ScreenParams.y)*720.;
    vec2 offset = vec2(1. * stepIns)/(mySize);

    float gray1 = deCode(texture2D(sdfImageTexture,uv+vec2(1,0)*offset));
    float gray11 = deCode(texture2D(sdfImageTexture,uv-vec2(1,0)*offset));
    float gray2 = deCode(texture2D(sdfImageTexture,uv+vec2(0,1)*offset));
    float gray22 = deCode(texture2D(sdfImageTexture,uv-vec2(0,1)*offset));

    vec2 grad=vec2(gray11-gray1,gray22-gray2)*10.*waterIns*deCode(texture2D(sdfImageTexture,uv));
    vec2 lastUV = mirror(uv+grad);
    vec4 resultCol = texture2D(inputImageTexture,lastUV);
    return resultCol;
}
void main()
{
    vec2 mySize = u_ScreenParams.xy / min(u_ScreenParams.x, u_ScreenParams.y) * 720.;
    vec2 offset = vec2(1.)/(mySize);
    vec4 resultCol = getCol(textureCoord) + getCol(textureCoord + offset*vec2(0.5,0))+getCol(textureCoord + offset*vec2(0,0.5))+getCol(textureCoord + offset*vec2(0.5,0.5));
    resultCol /= 4.;
    gl_FragColor = vec4(resultCol);
}
]]

Wave = {}

function Wave:matchWithId(effectId)
    return 'KFM KSkr Wave' == effectId
end

function Wave.createWithId(effectId)
    if not Wave:matchWithId(effectId) then
        return nil
    end
    local o = {
        circleProgram = {},
        blurX0Program = {},
        blurY0Program = {},
        blurX1Program = {},
        blurY1Program = {},
        waterProgram = {},
        adjustSpeed = 0,
        adjustSize = 0,
        adjustIntensity = 0,
        adjustBlur = 0,
        AdjustHorizontalShift = 0,
        AdjustVerticalShift = 0,
        currentWidth = 0,
        currentHeight = 0,
        currentTime = 0
    }
    o = newObject(o, Wave)
    o:init()
    return o;
end

function Wave:init()
    self.circleProgram = CGE.ProgramObject()
    self.circleProgram:bindAttribLocation('position', 0)
    self.circleProgram:initWithShaderStrings(vs, circle_fs)
    self.circleProgram:bind()
    self.circleProgram:sendUniformi('inputImageTexture', 0)

    self.blurX0Program = CGE.ProgramObject()
    self.blurX0Program:bindAttribLocation('position', 0)
    self.blurX0Program:initWithShaderStrings(vs, blurX0_fs)
    self.blurX0Program:bind()
    self.blurX0Program:sendUniformi('inputImageTexture', 0)

    self.blurY0Program = CGE.ProgramObject()
    self.blurY0Program:bindAttribLocation('position', 0)
    self.blurY0Program:initWithShaderStrings(vs, blurY0_fs)
    self.blurY0Program:bind()
    self.blurY0Program:sendUniformi('inputImageTexture', 0)

    self.blurX1Program = CGE.ProgramObject()
    self.blurX1Program:bindAttribLocation('position', 0)
    self.blurX1Program:initWithShaderStrings(vs, blurX1_fs)
    self.blurX1Program:bind()
    self.blurX1Program:sendUniformi('inputImageTexture', 0)

    self.blurY1Program = CGE.ProgramObject()
    self.blurY1Program:bindAttribLocation('position', 0)
    self.blurY1Program:initWithShaderStrings(vs, blurY1_fs)
    self.blurY1Program:bind()
    self.blurY1Program:sendUniformi('inputImageTexture', 0)

    self.waterProgram = CGE.ProgramObject()
    self.waterProgram:bindAttribLocation('position', 0)
    self.waterProgram:initWithShaderStrings(vs, water_fs)
    self.waterProgram:bind()
    self.waterProgram:sendUniformi('inputImageTexture', 0)
    self.waterProgram:sendUniformi('sdfImageTexture', 1)

    local buffer = {}
    glGenBuffers(1,buffer)
    self.vbo = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
end

function Wave:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- AdjustSpeed
        self.adjustSpeed = (0.85 * val1 / 100.0 + 0.15) * 2.4
    elseif index == 2 then
        -- AdjustSize
        self.adjustSize = val1 / 100.0
    elseif index == 3 then
        -- AdjustIntensity
        self.adjustIntensity = val1 / 100.0
    elseif index == 4 then
        -- AdjustBlur
        self.adjustBlur = val1 / 100.0
    elseif index == 5 then
        -- AdjustHorizontalShift
        self.adjustHorizontalShift = val1 / 100.0 
    elseif index == 6 then
        -- AdjustVerticalShift
        self.adjustVerticalShift = val1 / 100.0
    end
end

function Wave:resize(width, height)

end

function Wave:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
end

function Wave:getDistance(point1, point2, nowWidth, nowHeight)
    local ratio = {nowWidth / math.min(nowWidth, nowHeight), nowHeight / math.min(nowWidth, nowHeight)}
    local nowPoint1 = {point1[1] * ratio[1], point1[2] * ratio[2]}
    local nowPoint2 = {point2[1] * ratio[1], point2[2] * ratio[2]}
    return math.sqrt(
        (nowPoint1[1] - nowPoint2[1]) * (nowPoint1[1] - nowPoint2[1]) +
            (nowPoint1[2] - nowPoint2[2]) * (nowPoint1[2] - nowPoint2[2])
    )
end

function Wave:updateTimeAndFrame(time, frame)
    self.currentTime = time
end

function Wave:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    local maxDistance = -1
    local pointsArray = {{1, 1}, {0, 1}, {1, 0}, {0, 0}}
    local centerPoint = {self.adjustHorizontalShift, self.adjustVerticalShift}
    for i = 1, 4 do
        local nowDistance = self:getDistance(centerPoint, pointsArray[i], self.currentWidth, self.currentHeight)
        maxDistance = nowDistance > maxDistance and nowDistance or maxDistance
    end

    local fbo1 = AESP:takeCachedFrameBuffer(1280 / self.currentHeight * self.currentWidth, 1280)
    fbo1:bind()
    self.circleProgram:bind()
    self.circleProgram:sendUniformf('u_ScreenParams', 1280 / self.currentHeight * self.currentWidth, 1280)
    self.circleProgram:sendUniformf('u_center', self.adjustHorizontalShift, self.adjustVerticalShift)
    self.circleProgram:sendUniformf('u_maxDistance', maxDistance + self.adjustSize * 0.2 + 0.01)
    self.circleProgram:sendUniformf('u_smoothDistance', 0.053)
    self.circleProgram:sendUniformf('u_circleWidth', self.adjustSize * 0.2 + 0.01)
    self.circleProgram:sendUniformf('u_circleDisWidthChange', 1.0)
    self.circleProgram:sendUniformf('u_circleDisSmoothChange', 1.0)
    self.circleProgram:sendUniformf('u_nowRadius', math.mod(self.currentTime * self.adjustSpeed, 2.0 * maxDistance))
    self.circleProgram:sendUniformf('u_nowRadius1', math.mod(self.currentTime * self.adjustSpeed + maxDistance, 2.0 * maxDistance))
    self.circleProgram:sendUniformf('u_mask', 1.0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw2
    local fbo2 = AESP:takeCachedFrameBuffer(1280 / self.currentHeight * self.currentWidth, 1280)
    fbo2:bind()
    self.blurX0Program:bind()
    self.blurX0Program:sendUniformf('u_ScreenParams', 1280 / self.currentHeight * self.currentWidth, 1280)
    self.blurX0Program:sendUniformf('blurSize', self.adjustBlur * 1.5 + 1.0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw3
    local fbo3 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo3:bind()
    self.blurY0Program:bind()
    self.blurY0Program:sendUniformf('u_ScreenParams', self.currentWidth, self.currentHeight)
    self.blurY0Program:sendUniformf('blurSize', self.adjustBlur * 1.5 + 1.0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw4
    fbo1:bind()
    self.blurX1Program:bind()
    self.blurX1Program:sendUniformf('u_ScreenParams', 1280 / self.currentHeight * self.currentWidth, 1280)
    self.blurX1Program:sendUniformf('blurSize', self.adjustBlur * 1.5 + 1.0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo3:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw5
    fbo2:bind()
    self.blurY1Program:bind()
    self.blurY1Program:sendUniformf('u_ScreenParams', 1280 / self.currentHeight * self.currentWidth, 1280)
    self.blurY1Program:sendUniformf('blurSize', self.adjustBlur * 1.5 + 1.0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw6
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    glViewport(0, 0, self.currentWidth, self.currentHeight)
    self.waterProgram:bind()
    self.waterProgram:sendUniformf('u_ScreenParams', self.currentWidth, self.currentHeight)
    self.waterProgram:sendUniformf('waterIns', 1.0)
    self.waterProgram:sendUniformf('stepIns', self.adjustIntensity * 0.8 + 0.05)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    AESP:recycleCachedFrameBuffer(fbo1)
    AESP:recycleCachedFrameBuffer(fbo2)
    AESP:recycleCachedFrameBuffer(fbo3)
end

function Wave:onDestroy()
end
    