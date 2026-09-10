// Cloudflare Worker - VPS流量消耗管理工具 CDN 代理
// 部署域名: xh.813099.xyz
// 功能: 代理 GitHub 原始文件，加速国内访问，并返回 X-SHA256 供安装脚本校验完整性

const GITHUB_BASE = 'https://raw.githubusercontent.com/charmtv/VPS/main';

// 路由白名单：用 Map 而非对象字面量，避免 'constructor' 等原型链属性被误判为命中
const ROUTE_MAP = new Map([
  ['/', '/install.sh'],
  ['/install.sh', '/install.sh'],
  ['/vpsflow_latest.sh', '/vpsflow_latest.sh'],
  ['/README.md', '/README.md'],
  // 兼容 v3.4.0 改名前已安装的客户端：旧文件名指向新脚本，
  // 这些客户端「检查脚本更新」时才能取到新版本并完成自动迁移。
  ['/milier_flow_latest.sh', '/vpsflow_latest.sh'],
]);

const UPSTREAM_CACHE_TTL = 60; // 秒，更新后快速生效

// 按文件后缀返回对应的 Content-Type
function contentTypeFor(path) {
  if (path.endsWith('.sh')) return 'text/plain; charset=utf-8';
  if (path.endsWith('.md')) return 'text/markdown; charset=utf-8';
  return 'application/octet-stream';
}

// 计算响应体的 SHA-256，输出小写 hex
async function sha256Hex(text) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export default {
  async fetch(request) {
    const path = new URL(request.url).pathname;
    const targetPath = ROUTE_MAP.get(path);

    if (targetPath === undefined) {
      return new Response('404 Not Found', { status: 404 });
    }

    try {
      const response = await fetch(`${GITHUB_BASE}${targetPath}`, {
        headers: {
          'User-Agent': 'Cloudflare-Worker-VPSFlow',
          Accept: 'text/plain',
        },
        cf: {
          cacheTtl: UPSTREAM_CACHE_TTL,
          cacheEverything: true,
        },
      });

      // 上游状态透传：404 保持 404，5xx 归一为 502，其余保留原状态码
      if (!response.ok) {
        const status = response.status >= 500 ? 502 : response.status;
        const text =
          status === 404 ? '404 Not Found'
          : status === 502 ? '502 Bad Gateway'
          : `Upstream Error ${status}`;
        return new Response(text, { status });
      }

      const body = await response.text();
      const checksum = await sha256Hex(body);

      return new Response(body, {
        status: 200,
        headers: {
          'Content-Type': contentTypeFor(targetPath),
          'Cache-Control': `public, max-age=${UPSTREAM_CACHE_TTL}`,
          'X-Powered-By': 'VPSFlow-CDN',
          'Access-Control-Allow-Origin': '*',
          'X-SHA256': checksum,
        },
      });
    } catch {
      return new Response('Service Unavailable', { status: 502 });
    }
  },
};
