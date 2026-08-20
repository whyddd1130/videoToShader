
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
local gauss_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 screenParams;
uniform float blurSize;
uniform float angle;

vec4 gauss_blur(sampler2D inputTexture, vec2 uv, float angle, float blurSize, vec2 uRenderSize)
{
    float half_gaussian_weight[9];

    float radian = 3.1415926 * angle / 180.0;
    vec2 dir = vec2(cos(radian), sin(radian));
    
    half_gaussian_weight[0] = 0.2;   //0.2;//0.137401;
    half_gaussian_weight[1] = 0.19;  //0.2;//0.125794;
    half_gaussian_weight[2] = 0.17;  //0.2;//0.106483;
    half_gaussian_weight[3] = 0.15;  //0.2;//0.080657;
    half_gaussian_weight[4] = 0.13;  //0.2;//0.054670;
    half_gaussian_weight[5] = 0.11;  //0.2;//0.033159;
    half_gaussian_weight[6] = 0.08;  //0.2;//0.017997;
    half_gaussian_weight[7] = 0.05;  //0.2;//0.008741;
    half_gaussian_weight[8] = 0.02;  //0.2;//0.003799;

    vec4 sum            = vec4(0.0);
    vec4 result         = vec4(0.0);
    vec2 unit_uv        = vec2(blurSize, blurSize * uRenderSize.x / uRenderSize.y)*1.25/ 720.;
    vec4 centerPixel    = texture2D(inputTexture, uv) * half_gaussian_weight[0];
    float sum_weight    = half_gaussian_weight[0];

    vec2 curPositiveCoordinate = uv;
    vec2 curNegativeCoordinate = uv;

    for(int i=1; i<9; i++)
    {
        curPositiveCoordinate    += dir * unit_uv;
        curNegativeCoordinate    -= dir * unit_uv;
        sum += texture2D(inputTexture, curPositiveCoordinate) * half_gaussian_weight[i];
        sum += texture2D(inputTexture, curNegativeCoordinate) * half_gaussian_weight[i];
        sum_weight += half_gaussian_weight[i] * 2.0;
    }
    
    result = (sum + centerPixel) / sum_weight;
    return result;
}

void main()
{
    vec2 screenSize = screenParams;
    vec2 uv1 = textureCoord;
    vec4 resColor = gauss_blur(inputImageTexture, uv1, angle, blurSize, screenSize);
    gl_FragColor = resColor;
}
]]

---@language GLSL
local cross_blur_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 radius;
uniform vec2 screenParams;

vec2 Mirror(vec2 _u)
{
    return abs(mod(_u-1.,2.)-1.);
}

float gaussianWeight(float dist, float stdDev)
{
    return exp(-dist / (2.0 * stdDev));
}

vec4 gaussianBlur(sampler2D inputTexture, vec2 textureCoordinate, vec2 stepUV, vec2 screenSize)
{
    const int blurRadius = 20;
    vec2 unitUV         = vec2(stepUV.x, stepUV.y*screenSize.x/screenSize.y)/720.;
    float stdDev        = 112.0;
    float sumWeight     = gaussianWeight(0.0,stdDev);
    vec4 curColor       = texture2D(inputTexture, textureCoordinate);    
    vec4 sumColor       = curColor*sumWeight;
    //horizontal
    for(int i=1;i<=blurRadius;i++)
    {
        vec2 textureCoordinateA = textureCoordinate+float(i)*unitUV;
        vec2 textureCoordinateB = textureCoordinate+float(-i)*unitUV;
        vec4 colorA = texture2D(inputTexture, Mirror(textureCoordinateA));
        vec4 colorB = texture2D(inputTexture, Mirror(textureCoordinateB));
        float curWeight = gaussianWeight(float(i),stdDev);
        sumColor += colorA*curWeight;
        sumColor += colorB*curWeight;
        sumWeight+= curWeight*2.0;
    }

    vec4 resultColor = sumColor/sumWeight;
    return resultColor;
}

void main()
{
    vec2 uv1 = textureCoord;
    vec4 res = texture2D(inputImageTexture, uv1);

    vec4 res_v = gaussianBlur(inputImageTexture, uv1, vec2(radius.x,0), screenParams.xy);
    vec4 res_h = gaussianBlur(inputImageTexture, uv1, vec2(0,radius.y), screenParams.xy);
    res = res_v * 0.5 + res_h * 0.5;

    gl_FragColor = res;
}
]]

---@language GLSL
local grey_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float threshould;

void main() 
{
    vec2 uv1 = textureCoord;
    vec4 res = texture2D(inputImageTexture, uv1);
    float grey = dot(res.rgb, vec3(0.299, 0.587, 0.114));
    res.rgb = step(threshould, res.rgb);
    gl_FragColor = res;
}
]]

---@language GLSL
local glow_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform sampler2D blurTex;

uniform float glow_intensity;

void main()
{
    vec2 uv1 = textureCoord;
    vec4 blurCol = texture2D(blurTex, uv1);
    vec4 inputCol = texture2D(inputImageTexture, uv1);

    float grey = dot(blurCol.rgb, vec3(0.299, 0.587, 0.114));
    vec4 res = inputCol + (blurCol * 0.5 + vec4(vec3(grey), blurCol.a) * 0.5) * glow_intensity;
    gl_FragColor = res;
}
]]

CrossBlur = {}

function CrossBlur:matchWithId(effectId)
    return 'KFM KSkr CrossBlur' == effectId
end

function CrossBlur.createWithId(effectId)
    if not CrossBlur:matchWithId(effectId) then
        return nil
    end
    local o = {
        gaussProgram = {},
        crossBlurProgram = {},
        greyProgram = {},
        glowProgram = {},
        speed = 0.0,
        horizontalShift = 0.0,
        verticalShift = 0.0,
        luminance = 0.0,
        reverseBlur = 0.0,
        blurSize = 0.0,
        currentWidth = 0,
        currentHeight = 0,
        currentTime = 0.0,
        progress = 0.0
    }
    o = newObject(o, CrossBlur)
    o:init()
    return o;
end

function CrossBlur:init()
    self.gaussProgram = CGE.ProgramObject()
    self.gaussProgram:bindAttribLocation('position', 0)
    self.gaussProgram:initWithShaderStrings(vs, gauss_fs)
    self.gaussProgram:bind()
    self.gaussProgram:sendUniformi('inputImageTexture', 0)

    self.crossBlurProgram = CGE.ProgramObject()
    self.crossBlurProgram:bindAttribLocation('position', 0)
    self.crossBlurProgram:initWithShaderStrings(vs, cross_blur_fs)
    self.crossBlurProgram:bind()
    self.crossBlurProgram:sendUniformi('inputImageTexture', 0)

    self.greyProgram = CGE.ProgramObject()
    self.greyProgram:bindAttribLocation('position', 0)
    self.greyProgram:initWithShaderStrings(vs, grey_fs)
    self.greyProgram:bind()
    self.greyProgram:sendUniformi('inputImageTexture', 0)

    self.glowProgram = CGE.ProgramObject()
    self.glowProgram:bindAttribLocation('position', 0)
    self.glowProgram:initWithShaderStrings(vs, glow_fs)
    self.glowProgram:bind()
    self.glowProgram:sendUniformi('inputImageTexture', 0)
    self.glowProgram:sendUniformi('blurTex', 1)

    local buffer = {}
    glGenBuffers(1,buffer)
    self.vbo = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
end

function CrossBlur:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- Speed
        self.speed = 1.5 * val1 / 100.0 + 0.5
        if val1 < 0.01 then
            self.speed = 0.0
        end
    elseif index == 2 then
        -- HorizontalShift
        self.horizontalShift = val1 / 100.0
    elseif index == 3 then
        -- VerticalShift
        self.verticalShift = val1 / 100.0
    elseif index == 4 then
        -- Luminance
        self.luminance = val1 / 100.0
    elseif index == 5 then
        -- Reverse
        self.reverseBlur = val1 / 100.0
    elseif index == 6 then
        -- BlurSize
        self.blurSize = val1 / 100.0
    elseif index == 7 then
        self.progress = val1 / 100.0
    end
end

function CrossBlur:remap(a, b, x)
    if x < a then return 0 end
    if x > b then return 1 end
    return (x-a)/(b-a)
end

function CrossBlur:clamp(min, max, value)
    return math.min(math.max(value, min), max)
end

function CrossBlur:resize(width, height)

end

function CrossBlur:updateTimeAndFrame(time, frame)
    self.currentTime = time
end

function CrossBlur:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height

    self.crossBlurProgram:bind()
    self.crossBlurProgram:sendUniformf('screenParams', width, height)
end

function CrossBlur:getBezierValue(controls, t)
    local ret = {}
    local xc1 = controls[1]
    local yc1 = controls[2]
    local xc2 = controls[3]
    local yc2 = controls[4]
    ret[1] = 3*xc1*(1-t)*(1-t)*t+3*xc2*(1-t)*t*t+t*t*t
    ret[2] = 3*yc1*(1-t)*(1-t)*t+3*yc2*(1-t)*t*t+t*t*t
    return ret
end

function CrossBlur:getBezierTfromX(controls, x)
    local ts = 0
    local te = 1
    -- divide and conque
    repeat
        local tm = (ts+te)/2
        local value = self:getBezierValue(controls, tm)
        if(value[1]>x) then
            te = tm
        else
            ts = tm
        end
    until(te-ts < 0.0001)

    return (te+ts)/2
end

function CrossBlur:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    local mProgress = self.speed * self.progress
    if mProgress > 1.0 then
        mProgress = 1.0
    end
    if self.reverseBlur > 0.5 then
        mProgress = 1.0 - mProgress
    end

    local controls = {0.0,0.25,0.58,1} 
    local tvalue = self:getBezierTfromX(controls, mProgress)
    mProgress = self:getBezierValue(controls, tvalue)[2]
    local progressTmp = 1.0 - mProgress

    local fbo1 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo1:bind()
    self.gaussProgram:bind()
    self.gaussProgram:sendUniformf('blurSize', self.blurSize * progressTmp)  
    self.gaussProgram:sendUniformf('angle', 0.0)
    self.gaussProgram:sendUniformf('screenParams', self.currentWidth, self.currentHeight)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local fbo2 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo2:bind()
    self.gaussProgram:bind()
    self.gaussProgram:sendUniformf('blurSize', self.blurSize * progressTmp)
    self.gaussProgram:sendUniformf('angle', 90.0)
    self.gaussProgram:sendUniformf('screenParams', self.currentWidth, self.currentHeight)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    fbo1:bind()
    self.crossBlurProgram:bind()
    self.crossBlurProgram:sendUniformf('radius', 8.0 * self.horizontalShift * progressTmp, 8.0 * self.verticalShift * progressTmp)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    fbo2:bind()
    self.greyProgram:bind()
    self.greyProgram:sendUniformf('threshould', 0.439)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local fbo5 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.5, self.currentHeight * 0.5)
    fbo5:bind()
    self.gaussProgram:bind()
    self.gaussProgram:sendUniformf('blurSize', 2.0)
    self.gaussProgram:sendUniformf('angle', 0.0)
    self.gaussProgram:sendUniformf('screenParams', self.currentWidth * 0.5, self.currentHeight * 0.5)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local fbo6 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.5, self.currentHeight * 0.5)
    fbo6:bind()
    self.gaussProgram:bind()
    self.gaussProgram:sendUniformf('blurSize', 2.0)
    self.gaussProgram:sendUniformf('angle', 90.0)
    self.gaussProgram:sendUniformf('screenParams', self.currentWidth * 0.5, self.currentHeight * 0.5)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo5:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    fbo5:bind()
    self.gaussProgram:bind()
    self.gaussProgram:sendUniformf('blurSize', 2.0)
    self.gaussProgram:sendUniformf('angle', 0.0)
    self.gaussProgram:sendUniformf('screenParams', self.currentWidth * 0.5, self.currentHeight * 0.5)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo6:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    fbo6:bind()
    self.gaussProgram:bind()
    self.gaussProgram:sendUniformf('blurSize', 2.0)
    self.gaussProgram:sendUniformf('angle', 90.0)
    self.gaussProgram:sendUniformf('screenParams', self.currentWidth * 0.5, self.currentHeight * 0.5)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo5:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    glViewport(0, 0, self.currentWidth, self.currentHeight)
    self.glowProgram:bind()
    self.glowProgram:sendUniformf('glow_intensity', 0.5 * self.luminance * progressTmp)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, fbo6:texId())
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    AESP:recycleCachedFrameBuffer(fbo1)
    AESP:recycleCachedFrameBuffer(fbo2)
    AESP:recycleCachedFrameBuffer(fbo5)
    AESP:recycleCachedFrameBuffer(fbo6)
end

function CrossBlur:onDestroy()
end
    