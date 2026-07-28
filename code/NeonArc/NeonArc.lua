--- NeonArc.lua
-- 高频霓虹电弧与等离子闪烁特效
-- 依附画面边缘的高频电弧，带有狂躁的锯齿闪电形态和高频闪烁

NeonArc = {}

function NeonArc:matchWithId(effectId)
    if effectId == "KFM KSkr NeonArc" then return true end
    return false
end

function NeonArc:createWithId(effectId)
    if not NeonArc:matchWithId(effectId) then return nil end
    local o = {
        program = nil,
        vbo = nil,
        currentWidth = 0,
        currentHeight = 0,
        currentTime = 0.0,
        -- 参数
        arcIntensity = 70.0,
        arcFrequency = 50.0,
        arcSpeed = 50.0,
        edgeThreshold = 30.0,
        arcColorHue = 200.0,
        colorSaturation = 80.0,
        flickerIntensity = 70.0,
        glitchStrength = 30.0,
        thickness = 40.0
    }
    setmetatable(o, {__index = self})
    o:init()
    return o
end

function NeonArc:init()
    local vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

attribute vec2 position;
varying vec2 textureCoord;

void main()
{
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

    local fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float uTime;
uniform vec2 uResolution;
uniform float uIntensity;
uniform float uFrequency;
uniform float uArcSpeed;
uniform float uEdgeThreshold;
uniform float uHue;
uniform float uSaturation;
uniform float uFlicker;
uniform float uGlitch;
uniform float uThickness;

// ========== 噪声函数 ==========

float hash(float n)
{
    return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash2(i);
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// fBm分形布朗运动 - 用于扭曲坐标制造锯齿闪电
float fbm(vec2 p)
{
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for(int i = 0; i < 5; i++)
    {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// Voronoi 用于电弧节点
float voronoi(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    float minDist = 1.0;
    for(int y = -1; y <= 1; y++)
    {
        for(int x = -1; x <= 1; x++)
        {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 point = hash2(i + neighbor) * vec2(1.0);
            vec2 diff = neighbor + point - f;
            float dist = length(diff);
            minDist = min(minDist, dist);
        }
    }
    return minDist;
}

// ========== 边缘检测 ==========

// Sobel边缘检测
float sobelEdge(sampler2D tex, vec2 uv, vec2 texelSize)
{
    float kernelX[9];
    kernelX[0] = -1.0; kernelX[1] = 0.0; kernelX[2] = 1.0;
    kernelX[3] = -2.0; kernelX[4] = 0.0; kernelX[5] = 2.0;
    kernelX[6] = -1.0; kernelX[7] = 0.0; kernelX[8] = 1.0;
    
    float kernelY[9];
    kernelY[0] = -1.0; kernelY[1] = -2.0; kernelY[2] = -1.0;
    kernelY[3] = 0.0;  kernelY[4] = 0.0;  kernelY[5] = 0.0;
    kernelY[6] = 1.0;  kernelY[7] = 2.0;  kernelY[8] = 1.0;
    
    float gx = 0.0;
    float gy = 0.0;
    
    int idx = 0;
    for(int j = -1; j <= 1; j++)
    {
        for(int i = -1; i <= 1; i++)
        {
            vec2 offset = vec2(float(i), float(j)) * texelSize;
            vec4 col = texture2D(tex, uv + offset);
            float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
            gx += lum * kernelX[idx];
            gy += lum * kernelY[idx];
            idx = idx + 1;
        }
    }
    
    return sqrt(gx * gx + gy * gy);
}

// 高频闪烁函数 - 阶梯状噪点
float flickerNoise(float t, float freq)
{
    float strobefreq = freq * 10.0;
    float stepped = floor(t * strobefreq) / strobefreq;
    float n = hash(stepped);
    return 0.5 + 0.5 * sin(t * freq * 6.28318 + n * 3.14159 * 2.0);
}

// 瞬态跳跃 - 离散随机闪烁
float snapFlicker(float t, float speed)
{
    float phase = t * speed;
    float cell = floor(phase);
    float local = fract(phase);
    float r = hash(cell);
    float threshold = 0.3 + 0.4 * r;
    float flash = step(threshold, local);
    return flash * r;
}

// HSV转RGB
vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// ========== 主渲染 ==========

void main()
{
    vec2 uv = textureCoord;
    vec2 texelSize = 1.0 / uResolution;
    
    // 采样原图
    vec4 baseColor = texture2D(inputImageTexture, uv);
    float luminance = dot(baseColor.rgb, vec3(0.299, 0.587, 0.114));
    
    // 1. 边缘检测
    float edge = sobelEdge(inputImageTexture, uv, texelSize * 1.5);
    float edgeMask = smoothstep(uEdgeThreshold * 0.01, uEdgeThreshold * 0.01 + 0.1, edge);
    
    // 2. 电弧几何扭曲 - fBm扭曲坐标制造锯齿闪电
    float noiseScale = 30.0 + uFrequency * 0.5;
    vec2 noiseCoord = uv * noiseScale + vec2(uTime * uArcSpeed * 0.1);
    
    // 多层fBm扭曲产生锯齿
    float n1 = fbm(noiseCoord);
    float n2 = fbm(noiseCoord * 2.0 + vec2(uTime * 5.0));
    float distortion = (n1 * 0.7 + n2 * 0.3) * 0.02 * (uThickness * 0.01);
    
    vec2 distortedUV = uv + vec2(distortion, distortion * 0.7);
    
    // Voronoi产生电弧节点
    float vorScale = 15.0 + uFrequency * 0.3;
    float vor = voronoi(distortedUV * vorScale + vec2(uTime * uArcSpeed * 0.2));
    float nodeMask = 1.0 - smoothstep(0.0, 0.15, vor);
    
    // 3. 高频闪烁控制 - 核心特效
    float flicker = flickerNoise(uTime, uFrequency);
    float snap = snapFlicker(uTime, uArcSpeed * 0.5);
    
    // 组合闪烁
    float flickerCombined = mix(flicker, snap, uFlicker * 0.01);
    flickerCombined = pow(flickerCombined, 1.5);
    
    // 4. 电弧强度计算
    float arcStrength = edgeMask * nodeMask;
    arcStrength *= flickerCombined;
    arcStrength *= uIntensity * 0.01;
    
    // 粗细变化 - 随机突变
    float thicknessNoise = noise(uv * 50.0 + vec2(uTime * 3.0));
    arcStrength *= 0.3 + thicknessNoise * 0.7;
    
    // 5. 电离色彩
    float hue = uHue / 360.0;
    float saturation = uSaturation * 0.01;
    vec3 arcColor = hsv2rgb(vec3(hue, saturation, 1.0));
    
    // 核心高光 - 纯白色
    vec3 coreColor = vec3(1.0);
    
    // 混合核心与边缘色
    vec3 finalColor = mix(arcColor, coreColor, arcStrength * 0.7);
    
    // 6. 故障色散 (Glitch Chromatic Aberration)
    float glitchAmount = uGlitch * 0.01 * flickerCombined;
    float aberrationShift = glitchAmount * 0.02 * sin(uTime * 50.0);
    
    // 高频闪烁峰值时RGB通道撕裂
    float peakFlash = step(0.8, flickerCombined) * flickerCombined;
    vec3 glitchColor = vec3(
        arcStrength * (1.0 + aberrationShift * 10.0),
        arcStrength,
        arcStrength * (1.0 - aberrationShift * 10.0)
    );
    finalColor = mix(finalColor, glitchColor, peakFlash * uGlitch * 0.01);
    
    // 7. 背景联动 - 闪电照亮环境
    float envFlash = flickerCombined * uIntensity * 0.002;
    vec3 envLight = baseColor.rgb * (1.0 + envFlash);
    
    // 8. Additive混合
    vec3 result = envLight + finalColor * arcStrength;
    
    // 过曝处理
    result = min(result, vec3(1.5));
    
    gl_FragColor = vec4(result, baseColor.a);
}
]]

    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation("position", 0)
    self.program:initWithShaderStrings(vs, fs)
    self.program:bind()
    self.program:sendUniformi("inputImageTexture", 0)

    local buffer = {}
    glGenBuffers(1, buffer)
    self.vbo = buffer[1]
    local vertices = {-1,-1, 1,-1, -1,1, 1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
end

function NeonArc:valueType(index)
    -- 1:arcIntensity, 2:arcFrequency, 3:arcSpeed
    -- 4:edgeThreshold, 5:arcColorHue, 6:colorSaturation
    -- 7:flickerIntensity, 8:glitchStrength, 9:thickness
    return FM.AEValueType_Float
end

function NeonArc:updateValue(index, val1, val2, val3)
    if index == 1 then
        self.arcIntensity = val1
    elseif index == 2 then
        self.arcFrequency = val1
    elseif index == 3 then
        self.arcSpeed = val1
    elseif index == 4 then
        self.edgeThreshold = val1
    elseif index == 5 then
        self.arcColorHue = val1
    elseif index == 6 then
        self.colorSaturation = val1
    elseif index == 7 then
        self.flickerIntensity = val1
    elseif index == 8 then
        self.glitchStrength = val1
    elseif index == 9 then
        self.thickness = val1
    end
end

function NeonArc:resize(width, height)
end

function NeonArc:updateTimeAndFrame(time, frame)
    self.currentTime = time
end

function NeonArc:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
end

function NeonArc:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    glViewport(0, 0, self.currentWidth, self.currentHeight)
    
    self.program:bind()
    self.program:sendUniformf("uTime", self.currentTime)
    self.program:sendUniformf("uResolution", self.currentWidth, self.currentHeight)
    self.program:sendUniformf("uIntensity", self.arcIntensity)
    self.program:sendUniformf("uFrequency", self.arcFrequency)
    self.program:sendUniformf("uArcSpeed", self.arcSpeed)
    self.program:sendUniformf("uEdgeThreshold", self.edgeThreshold)
    self.program:sendUniformf("uHue", self.arcColorHue)
    self.program:sendUniformf("uSaturation", self.colorSaturation)
    self.program:sendUniformf("uFlicker", self.flickerIntensity)
    self.program:sendUniformf("uGlitch", self.glitchStrength)
    self.program:sendUniformf("uThickness", self.thickness)
    
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
    
    glDisableVertexAttribArray(0)
end

function NeonArc:onDestroy()
    if self.vbo then
        local buffer = {self.vbo}
        glDeleteBuffers(1, buffer)
    end
end