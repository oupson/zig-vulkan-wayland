#version 450

layout(binding = 1) uniform sampler2D texSampler;

layout(binding = 0) uniform UniformBufferObject {
    vec4 cameraPos;
    vec2 cameraRot;
    vec2 resolution;
} ubo;

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

float sdSphere(vec3 p, float s) {
    return length(p) - s;
}

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// distance to scene
float map(vec3 p) {
    vec3 spherePos = vec3(2, 0.0, 0);
    float sphere = sdSphere(p - spherePos, 0.5);

    vec3 q = p;
    q = fract(p) - 0.5;

    float box = sdBox(q, vec3(0.1)); // cube sdf

    return min(sphere, box);
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
    float y = -sin(pitch);
    float z = cos(yaw) * cos(pitch);

    vec3 rd = normalize(vec3(uv * fov, 1)); // Ray direction // TODO pitch etc
    vec3 col = vec3(0);

    // Vertical ORDER IS IMPORTANT
    // ro.yz *= rot2D(-yaw);
    rd.yz *= rot2D(-pitch);

    // Horizontal camera rotation
    //ro.xz *= rot2D(-pitch);
    rd.xz *= rot2D(-yaw);

    float t = 0.0;

    // Raymarching
    // TODO ajust 80
    for (int i = 0; i < 80; i++) {
        vec3 p = ro + rd * t; // Position along the ray

        float d = map(p); // Current distance to the scene

        t += d; // March the ray
        col = vec3(i) / 80.0;

        if (d < 0.001 || t > 100.0) break; // Close enough || LOS
    }
    // Coloring
    // col = vec3(t * 0.2);

    outColor = vec4(col, 1.0);
}
