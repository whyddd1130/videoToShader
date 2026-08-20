
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
local blur_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

#define spatialWeight 10.0
#define tonalWeight 0.1
#define PI 3.141592
#define TAU (PI * 2.0)

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform vec2 imageSize;
uniform float detailRadius;
uniform float detailThreshold;
uniform int direction;

float Gaussian(float d, float sigma) 
{
    return 1.0 / (sigma * sqrt(TAU)) * exp(-(d * d) / (2.0 * sigma * sigma));
}

vec4 Gaussian(vec4 d, float sigma) 
{
    return 1.0 / (sigma * sqrt(TAU)) * exp(-(d * d) / (2.0 * sigma * sigma));
}

vec4 WeightFunction(vec2 s, vec2 s0) 
{
    float spacialDifference = length(s - s0); //空间距离
    vec4 tonalDifference = texture2D(inputImageTexture, s) - texture2D(inputImageTexture, s0); //像素距离

    float tonalDifferenceIntensity = 0.2126 * tonalDifference.r + 0.7152 * tonalDifference.g + 0.0722 * tonalDifference.b;
    return Gaussian(spacialDifference, spatialWeight) * Gaussian(vec4(vec3(tonalDifferenceIntensity), tonalDifference.a), tonalWeight * detailThreshold);
}

void main() 
{
    vec4 numerator = vec4(0.0);  
    vec4 denominator = vec4(0.0); 

    if(direction == 1)
    {
        for (int k = 0; k < int(detailRadius) * 2 + 1; k++) 
        {
            vec2 idOffset = vec2(textureCoord.x, textureCoord.y + (float(k) - detailRadius) / imageSize.y);

            if (idOffset.y >= 0.0 && idOffset.y < 1.0) 
            {
                vec4 weight = WeightFunction(idOffset, textureCoord);
                numerator += texture2D(inputImageTexture, idOffset) * weight;
                denominator += weight;
            }
        }
    }
    if(direction == 2)
    {
        for (int k = 0; k < int(detailRadius) * 2 + 1; k++) 
        {
            vec2 idOffset = vec2(textureCoord.x + (float(k) - detailRadius) / imageSize.x, textureCoord.y);

            if (idOffset.x >= 0.0 && idOffset.x < 1.0) 
            {
                vec4 weight = WeightFunction(idOffset, textureCoord);
                numerator += texture2D(inputImageTexture, idOffset) * weight;
                denominator += weight;
            }
        }
    }
    gl_FragColor = numerator / denominator;
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
uniform sampler2D originImage;

uniform float steps;
uniform float smoothness;

void main() 
{
    vec4 color = texture2D(inputImageTexture, textureCoord);
    vec3 coefficients = vec3(0.2126, 0.7152, 0.0722);
    float grey = dot(coefficients, color.rgb);

    float brightness = 0.9;
    grey = clamp(grey * brightness, 0.0, 1.0);

    float levels = steps - 1.0;
    float posterized = floor(grey * levels + 0.5) / levels;

    //float contrast = 1.3;
    //float contrasted = clamp(contrast * (posterized - 0.5) + 0.5, 0.0, 1.0);

    float r = clamp(color.r * posterized / grey, 0.0, 1.0);
    float g = clamp(color.g * posterized / grey, 0.0, 1.0);
    float b = clamp(color.b * posterized / grey, 0.0, 1.0);

    vec4 originColor = texture2D(inputImageTexture, textureCoord);
    r = mix(r, originColor.r, smoothness);
    g = mix(g, originColor.g, smoothness);
    b = mix(b, originColor.b, smoothness);

    gl_FragColor = vec4(r, g, b, color.a);
}
]]

---@language GLSL
local sobel_fs = [[
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
]]

Cartoon = {}

function Cartoon:matchWithId(effectId)
    return 'KFM KSkr Cartoon' == effectId
end

function Cartoon.createWithId(effectId)
    if not Cartoon:matchWithId(effectId) then
        return nil
    end
    local o = {
        vertexBuffer = 0,
        program = {},
        blurProgram = {},
        edgeDeteProgram = {},
        cachedFbos = {},
        currentWidth = 0,
        currentHeight = 0,
        renderType = 0
    }
    o = newObject(o, Cartoon)
    o:init()
    return o;
end

function Cartoon:init()
    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation('position', 0)
    self.program:initWithShaderStrings(vs, fs)
    self.program:bind()
    self.program:sendUniformi('inputImageTexture', 0)
    self.program:sendUniformi('originImage', 1)

    self.blurProgram = CGE.ProgramObject()
    self.blurProgram:bindAttribLocation('position', 0)
    self.blurProgram:initWithShaderStrings(vs, blur_fs)
    self.blurProgram:bind()
    self.blurProgram:sendUniformi('inputImageTexture', 0)

    self.edgeDeteProgram = CGE.ProgramObject()
    self.edgeDeteProgram:bindAttribLocation('position', 0)
    self.edgeDeteProgram:initWithShaderStrings(vs, sobel_fs)
    self.edgeDeteProgram:bind()
    self.edgeDeteProgram:sendUniformi('inputImageTexture', 0)

    local buffer = {}
    glGenBuffers(1,buffer)
    self.vertexBuffer = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
end

function Cartoon:valueType(index)
    if index == 1 then
        -- Render
        return FM.AEValueType_OneDInt
    elseif index == 2 then
        -- Detail Radius
        return FM.AEValueType_OneDFloat
    elseif index == 3 then
        -- Detail Threshold
        return FM.AEValueType_OneDFloat
    elseif index == 4 then
        -- shading Steps
        return FM.AEValueType_OneDFloat
    elseif index == 5 then
        -- Shading Smoothness
        return FM.AEValueType_OneDFloat
    elseif index == 6 then
        -- Edge Threshold
        return FM.AEValueType_OneDFloat
    elseif index == 7 then
        -- Edge Width
        return FM.AEValueType_OneDFloat
    elseif index == 8 then
        -- Edge Opacity
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function Cartoon:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- Render
        -- val1 is a index(starts with 1, not 0) of [Fill | Edges | Fill And Edges]
        self.renderType = val1
        self.edgeDeteProgram:bind()
        self.edgeDeteProgram:sendUniformi("renderType", val1)
    elseif index == 2 then
        -- Detail Radius
        self.blurProgram:bind()
        self.blurProgram:sendUniformf("detailRadius", val1)
    elseif index == 3 then
        -- Detail Threshold
        self.blurProgram:bind()
        self.blurProgram:sendUniformf("detailThreshold", val1 * 0.01)
    elseif index == 4 then
        -- shading Steps
        self.program:bind()
        self.program:sendUniformf("steps", val1)
    elseif index == 5 then
        -- Shading Smoothness
        self.program:bind()
        self.program:sendUniformf("smoothness", val1 * 0.01)
    elseif index == 6 then
        -- Edge Threshold
        self.edgeDeteProgram:bind()
        self.edgeDeteProgram:sendUniformf("edgeThreshold", val1)
    elseif index == 7 then
        -- Edge Width
        self.edgeDeteProgram:bind()
        self.edgeDeteProgram:sendUniformf("edgeWidth", val1)
    elseif index == 8 then
        -- Edge Opacity
        self.edgeDeteProgram:bind()
        self.edgeDeteProgram:sendUniformf("edgeOpacity", val1)
    end
end

function Cartoon:takeCachedFrameBuffer(fboWidth, fboHeight)
    if AESP.takeCachedFrameBuffer ~= nil then
        return AESP:takeCachedFrameBuffer(fboWidth, fboHeight)
    end
    for i=1, #self.cachedFbos, 1 do
        local fbo = self.cachedFbos[i]
        if fbo._isHold == false and fbo._width == fboWidth and fbo._height == fboHeight then
            fbo._isHold = true
            return fbo
        end
    end

    local fbo = {
        _width = fboWidth,
        _height = fboHeight,
        _texId = 0,
        _fboId = 0,
        _isHold = false,

        width = function(self) return self._width end,
        height = function(self) return self._height end,
        texId = function(self) return self._texId end,
        fboId = function(self) return self._fboId end,

        init = function(self)
            self:release()
            self._texId = cgeGenBlackTexture(self._width, self._height, GL_RGBA)
            local buffer = {}
            glGenFramebuffers(1, buffer)
            self._fboId = buffer[1]
            glBindFramebuffer(GL_FRAMEBUFFER, self._fboId)
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, self._texId, 0);
        end,

        release = function(self)
            if self._texId ~= 0 then glDeleteTextures(1, {self._texId}) end
            if self._fboId ~= 0 then glDeleteFramebuffers(1, {self._fboId}) end
            self._texId = 0
            self._fboId = 0
        end,

        bind = function(self) 
            glBindFramebuffer(GL_FRAMEBUFFER, self._fboId);
            glViewport(0, 0, self._width, self._height);
        end
    }
    fbo:init()
    fbo._isHold = true
    self.cachedFbos[#self.cachedFbos + 1] = fbo
    return fbo
end

function Cartoon:recycleCachedFrameBuffer(fbo)
    if AESP.recycleCachedFrameBuffer ~= nil then
        return AESP:recycleCachedFrameBuffer(fbo)
    end
    fbo._isHold = false
end

function Cartoon:customResize(width, height)
    if self.currentWidth ~= width or self.currentHeight ~= height then
        self.currentWidth = width
        self.currentHeight = height

        self.blurProgram:bind()
        self.blurProgram:sendUniformf("imageSize", width, height)
        self.edgeDeteProgram:bind()
        self.edgeDeteProgram:sendUniformf("samplerSteps", 1 / width, 1 / height)
    end
end

function Cartoon:resize(width, height)

end

function Cartoon:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    local curFbo = self:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    curFbo:bind()
    self.blurProgram:bind()
    self.blurProgram:sendUniformi("direction", 1)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local lastFbo = self:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    lastFbo:bind()
    self.blurProgram:bind()
    self.blurProgram:sendUniformi("direction", 2)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, curFbo:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    if self.renderType == 1 then
        glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
        self.program:bind()
        glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, lastFbo:texId())
        glActiveTexture(GL_TEXTURE1)
        glBindTexture(GL_TEXTURE_2D, inputTex)
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
    end

    if self.renderType == 2 then
        glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
        self.edgeDeteProgram:bind()
        glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, lastFbo:texId())
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
    end

    if self.renderType == 3 then
        curFbo:bind()
        self.program:bind()
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, lastFbo:texId())
        glActiveTexture(GL_TEXTURE1)
        glBindTexture(GL_TEXTURE_2D, inputTex)
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

        glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
        self.edgeDeteProgram:bind()
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, curFbo:texId())
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
    end

    self:recycleCachedFrameBuffer(curFbo)
    self:recycleCachedFrameBuffer(lastFbo)
end

function Cartoon:onDestroy()
    glDeleteBuffers(1, {self.vertexBuffer})
    for i=1, #self.cachedFbos, 1 do
        self.cachedFbos[i]:release()
    end
    self.cachedFbos = {}
end
    