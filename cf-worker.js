// Cloudflare Worker - 米粒儿VPS流量消耗管理工具 CDN 代理
// 部署域名: xh.813099.xyz
// 功能: 代理 GitHub 原始文件，加速国内访问，并返回 X-SHA256 供安装脚本校验完整性

const GITHUB_BASE = 'https://raw.githubusercontent.com/charmtv/VPS/main';

// 路由映射表（严格白名单：仅允许以下路径）
const ROUTE_MAP = {
  '/': '/install.sh',
  '/install.sh': '/install.sh',
  '/milier_flow_latest.sh': '/milier_flow_latest.sh',
  '/README.md': '/README.md',
};

// 改动点：按文件后缀映射 Content-Type（.sh / .md 分别返回对应类型）
function contentTypeFor(path) {
  if (path.endsWith('.sh')) return 'text/plain; charset=utf-8';
  if (path.endsWith('.md')) return 'text/markdown; charset=utf-8';
  return 'application/octet-stream';
}

// 改动点：将响应体 SHA-256 摘要转为小写 hex 字符串
async function sha256Hex(text) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    // 改动点：严格白名单，未命中直接返回 404，不再拼接任意路径
    if (!(path in ROUTE_MAP)) {
      return new Response('404 Not Found', { status: 404 });
    }

    const targetPath = ROUTE_MAP[path];
    const targetUrl = `${GITHUB_BASE}${targetPath}`;

    try {
      const response = await fetch(targetUrl, {
        headers: {
          'User-Agent': 'Cloudflare-Worker-MilierVPS',
          'Accept': 'text/plain',
        },
        cf: {
          // 缓存 60 秒，更新后快速生效
          cacheTtl: 60,
          cacheEverything: true,
        },
      });

      // 改动点：上游状态透传（404→404；>=500→502；其余非 ok 保持原状态）
      if (!response.ok) {
        const status = response.status >= 500 ? 502 : response.status;
        const text = status === 404 ? '404 Not Found'
          : status === 502 ? '502 Bad Gateway'
          : `Upstream Error ${status}`;
        return new Response(text, { status });
      }

      const body = await response.text();

      // 改动点：计算 SHA-256 并以 X-SHA256 响应头返回
      const checksum = await sha256Hex(body);

      return new Response(body, {
        status: 200,
        headers: {
          'Content-Type': contentTypeFor(targetPath),
          'Cache-Control': 'public, max-age=60',
          'X-Powered-By': 'MilierVPS-CDN',
          'Access-Control-Allow-Origin': '*',
          'X-SHA256': checksum,
        },
      });
    } catch (err) {
      return new Response('Service Unavailable', { status: 502 });
    }
  },
};
