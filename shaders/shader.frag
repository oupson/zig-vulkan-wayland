#version 450

layout(binding = 1) uniform sampler2D texSampler;

layout(binding = 0) uniform UniformBufferObject {
    vec4 cameraPos;
    vec2 cameraRot;
    vec2 resolution;
} ubo;

layout(std430, binding = 2) readonly buffer VoxelsBuffer {
    uint voxels[32 * 32 * 32 * 10 * 10 * 10];
} voxels;

layout(location = 0) out vec4 outColor;

// Rodrigues rotation
// ax is normalized
// ro is radian
vec3 rot3D(vec3 p, vec3 ax, float ro) {
    return mix(dot(ax, p) * ax, p, cos(ro)) + cross(ax, p) * sin(ro);
}

mat2 rot2D(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c);
}

bvec3 isEqual(vec3 a, vec3 b) {
    return lessThan(abs(a - b), vec3(0.001));
}

bool get_voxel(ivec3 pos) {
    ivec3 real_pos = pos + 5 * 32;

    ivec3 chunk_pos = real_pos / 32;
    ivec3 inpos = real_pos - (chunk_pos * 32);

    int chunk_index = chunk_pos.z * 10 * 10 + chunk_pos.y * 10 + chunk_pos.x;
    int chunk_in_index =
        inpos.z * 32 * 32 + inpos.y * 32 + inpos.x;

    return all(greaterThanEqual(real_pos, ivec3(0))) && voxels.voxels[(chunk_index * 32 * 32 * 32) + chunk_in_index] != 0;
}

#define MAX_RAY_STEPS 64
vec3 raytrace(vec3 ray_pos, vec3 ray_dir) {
    ivec3 map_pos = ivec3(floor(ray_pos + 0.));

    vec3 color = vec3(1.0);
    vec3 side_dist;
    bvec3 mask;

    vec3 delta_dist;
    {
        delta_dist = 1.0 / abs(ray_dir);
        ivec3 ray_step = ivec3(sign(ray_dir));
        side_dist = (sign(ray_dir) * (vec3(map_pos) - ray_pos) + (sign(ray_dir) * 0.5) + 0.5) * delta_dist;

        int i;
        for (i = 0; i < MAX_RAY_STEPS; i++)
        {
            if (get_voxel(map_pos)) break;

            mask = lessThanEqual(side_dist.xyz, min(side_dist.yzx, side_dist.zxy));
            side_dist += vec3(mask) * delta_dist;
            map_pos += ivec3(vec3(mask)) * ray_step;
        }

        if (i == MAX_RAY_STEPS) {
            return vec3(0, 0, 0);
        }

        color *= dot(vec3(0.5, 1.0, 0.75), vec3(mask));
    }

    float d = length(vec3(mask) * (side_dist - delta_dist));

    vec3 dst = ray_pos + ray_dir * d;

    vec3 voxel_pos = vec3(map_pos);

    vec3 normals = vec3(isEqual(voxel_pos, dst)) * -1.0
            + vec3(isEqual(voxel_pos + 1.0, dst));

    if (normals.z == -1 || normals.z == 1) {
        color *= texture(texSampler, dst.xy).xyz;
    } else if (normals.y == -1 || normals.y == 1) {
        color *= texture(texSampler, dst.xz).xyz;
    } else {
        color *= texture(texSampler, dst.yz).xyz;
    }

    return color;
}

void main() {
    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = (gl_FragCoord.xy * 2.0 - ubo.resolution.xy) / ubo.resolution.y;
    float fov = ubo.cameraPos.w;

    // Initialization
    vec3 ro = ubo.cameraPos.xyz; // Camera position (ray origin)

    float yaw = ubo.cameraRot.x;
    float pitch = ubo.cameraRot.y;
    float x = sin(yaw) * cos(pitch);
    float y = sin(pitch);
    float z = cos(yaw) * cos(pitch);

    vec3 rd = vec3(uv * fov, 1);

    // Vertical ORDER IS IMPORTANT
    // ro.yz *= rot2D(-yaw);
    rd.yz *= rot2D(-pitch);

    // Horizontal camera rotation
    //ro.xz *= rot2D(-pitch);
    rd.xz *= rot2D(-yaw);

    rd = normalize(rd);

    rd.y *= -1;
    ro.y *= -1;

    outColor = vec4(raytrace(ro, rd), 1.0);
}
