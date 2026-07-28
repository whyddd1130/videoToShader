
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
uniform vec2 imageSize;

uniform float radius;
uniform float positionX;
uniform float positionY;
uniform float positionZ;
uniform float rotationX;
uniform float rotationY;
uniform float rotationZ;
uniform int renderOrder;
uniform int render;

const float PI = 3.1415926;
vec2 castuv = vec2(0.0);

struct cylinder_t
{
    vec3 p;
    float height;
    float radius;
    mat3 r;
};

mat3 rot_x(float ang)
{
    float sang = sin(ang);
    float cang = cos(ang);
    return mat3
    (
        vec3(1.0, 0.0, 0.0),
        vec3(0.0, cang,-sang),
        vec3(0.0, sang, cang)
    );
}

mat3 rot_y(float ang)
{
    float sang = sin(ang);
    float cang = cos(ang);
    return mat3
    (
        vec3( cang, 0.0, sang),
        vec3(  0.0, 1.0, 0.0),
        vec3(-sang, 0.0, cang)
    );
}

mat3 rot_z(float ang)
{
    float sang = sin(ang);
    float cang = cos(ang);
    return mat3
    (
        vec3( cang, sang, 0.0),
        vec3(-sang, cang, 0.0),
        vec3(0.0, 0.0, 1.0)
    );
}  

mat3 rot_yaw_pitch_roll(vec3 ypr)
{
    if(renderOrder == 1)
    {
        return rot_z(ypr.z) * rot_y(ypr.y) * rot_x(ypr.x);
    }
    if(renderOrder == 2)
    {
        return rot_y(ypr.y) * rot_z(ypr.z) * rot_x(ypr.x);   
    }
    if(renderOrder == 3)
    {
        return rot_z(ypr.z) * rot_x(ypr.x) * rot_y(ypr.y);   
    }
    if(renderOrder == 4)
    {
        return rot_x(ypr.x) * rot_z(ypr.z) * rot_y(ypr.y);   
    }
    if(renderOrder == 5)
    {
        return rot_y(ypr.y) * rot_x(ypr.x) * rot_z(ypr.z);   
    }
    if(renderOrder == 6)
    {
        return rot_x(ypr.x) * rot_y(ypr.y) * rot_z(ypr.z);   
    }
}

bool cylinder_raycast(cylinder_t cylinder, vec3 orig, vec3 dir, int renderType)
{
    vec3 local_orig = cylinder.r * (orig - cylinder.p);
    vec3 local_dir = cylinder.r * dir;
    float r = cylinder.radius;
    float rsq = r * r;
    float hh = cylinder.height / 2.;

    bool isinside = false;
    
    float ray_proj = dot(-local_orig.xz, normalize(local_dir.xz));
    float orig_to_axis_dist_sq = dot(local_orig.xz, local_orig.xz);
    float axis_to_ray_sq = max(0., orig_to_axis_dist_sq - ray_proj * ray_proj);

    if(axis_to_ray_sq > rsq) 
        return false;

    float foo = sqrt(rsq - axis_to_ray_sq);
    float dist1 = ray_proj - foo;
    float dist2 = ray_proj + foo;

    if(orig_to_axis_dist_sq < rsq && abs(local_orig.y) <= hh) 
        isinside = true;
    if(isinside && renderType != 3)
        return false;

    float intersect_dist = 0.0;
    if(renderType == 3) 
        intersect_dist = dist2 / length(local_dir.xz);
    else 
        intersect_dist = dist1 / length(local_dir.xz);
    
    vec3 local_cast = local_orig + local_dir * intersect_dist;
    vec3 local_normal = vec3(local_cast.xz, 0.).xzy / r;
    if(renderType == 3)
    {
        local_normal = -local_normal;
    }
    
    if(abs(local_cast.y) > hh)
    {
        if(renderType == 2 || renderType == 3)
        {
            return false;
        }  
        float plane1 = (local_orig.y - hh) / (-local_dir.y);
        float plane2 = (local_orig.y + hh) / (-local_dir.y);

        if(renderType == 3)
            intersect_dist = max(plane1, plane2);
        else 
            intersect_dist = min(plane1, plane2);

        local_normal = vec3(0.0, -sign(local_dir.y), 0.0);
        local_cast = local_orig + local_dir * intersect_dist;

        if(renderType == 1)
        {
            if(length(local_cast.xz) > r) 
            {
                return false;
            }
            castuv = (local_cast.xz + vec2(r)) / (r * 2.);
        }          
    }
    else
    {
        castuv.x = (atan(local_normal.z, local_normal.x) / PI) * .5 + .5;
        castuv.y = (local_cast.y + hh) / cylinder.height;
    }
    
    vec3 castpoint = orig + dir * intersect_dist;
    vec3 normal = local_normal * cylinder.r;
    return true;
}

void main() 
{
    castuv = textureCoord;
    vec2 xy = textureCoord - vec2(0.5);
    vec4 resultColor = vec4(0.0);

    mat3 viewmat = rot_yaw_pitch_roll(vec3(rotationX, rotationY, rotationZ));
    
    mat3 rot_m = rot_yaw_pitch_roll(vec3(0.0));
    vec3 ray = normalize(vec3(xy, 1.0)) * viewmat;
    vec3 eyepos = vec3(-positionX * 0.01, positionY * 0.01, -positionZ * 0.01) * viewmat;

    cylinder_t cyl = cylinder_t(vec3(0.0, 0.0, 0.0), 5., radius, rot_m);
    
    if(cylinder_raycast(cyl, eyepos, ray, render))
    {
        resultColor = texture2D(inputImageTexture, castuv);
    }
    gl_FragColor = resultColor;
}
]]

CCCylinder = {}

function CCCylinder:matchWithId(effectId)
    return 'KFM KSkr CCCylinder' == effectId
end

function CCCylinder.createWithId(effectId)
    if not CCCylinder:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {},
        program = {}
    }
    o = newObject(o, CCCylinder)
    o:init()
    return o;
end

function CCCylinder:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
    self.program = self.drawer:getProgram()
end

function CCCylinder:valueType(index)
    if index == 1 then
        -- Radius
        return FM.AEValueType_OneDFloat
    elseif index == 2 then
        -- PositionX
        return FM.AEValueType_OneDFloat
    elseif index == 3 then
        -- PositionY
        return FM.AEValueType_OneDFloat
    elseif index == 4 then
        -- PositionZ
        return FM.AEValueType_OneDFloat
    elseif index == 5 then
        -- RotationX
        return FM.AEValueType_OneDFloat
    elseif index == 6 then
        -- RotationY
        return FM.AEValueType_OneDFloat
    elseif index == 7 then
        -- RotationZ
        return FM.AEValueType_OneDFloat
    elseif index == 8 then
        -- RenderOrder
        return FM.AEValueType_OneDInt
    elseif index == 9 then
        -- Render
        return FM.AEValueType_OneDInt
    end
    return FM.AEValueType_No_Value
end

function CCCylinder:updateValue(index, val1, val2, val3)
    self.program:bind()
    if index == 1 then
        -- Radius
        self.program:sendUniformf("radius", val1 * 0.01)
    elseif index == 2 then
        -- PositionX
        self.program:sendUniformf("positionX", val1)
    elseif index == 3 then
        -- PositionY
        self.program:sendUniformf("positionY", val1)
    elseif index == 4 then
        -- PositionZ
        self.program:sendUniformf("positionZ", val1)
    elseif index == 5 then
        -- RotationX
        self.program:sendUniformf("rotationX", val1)
    elseif index == 6 then
        -- RotationY
        self.program:sendUniformf("rotationY", val1)
    elseif index == 7 then
        -- RotationZ
        self.program:sendUniformf("rotationZ", val1)
    elseif index == 8 then
        -- RenderOrder
        -- val1 is a index(starts with 1, not 0) of [XYZ | XZY | YXZ | YZX | ZXY | ZYX]
        self.program:sendUniformi("renderOrder", val1)
    elseif index == 9 then
        -- Render
        -- val1 is a index(starts with 1, not 0) of [Full | Outside | Inside]
        self.program:sendUniformi("render", val1)
    end
end

function CCCylinder:resize(width, height)
    self.program:bind()
    self.program:sendUniformf("imageSize", width, height)
end

function CCCylinder:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function CCCylinder:onDestroy()
end
    
