// Cloudflare Worker - 米粒儿VPS流量消耗管理工具 CDN 代理
// 部署域名: xh.813099.xyz
// 功能: 代理 GitHub 原始文件，加速国内访问

const GITHUB_BASE = 'https://raw.githubusercontent.com/charmtv/VPS/main';

// 路由映射表
const ROUTE_MAP = {
  '/': '/install.sh',
  '/install.sh': '/install.sh',
  '/milier_flow_latest.sh': '/milier_flow_latest.sh',
  '/README.md': '/README.md',
};

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    // 查找映射路径，未匹配则直接拼接
    const targetPath = ROUTE_MAP[path] || path;
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

      if (!response.ok) {
        return new Response('404 Not Found', { status: 404 });
      }

      const body = await response.text();

      return new Response(body, {
        status: 200,
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          'Cache-Control': 'public, max-age=60',
          'X-Powered-By': 'MilierVPS-CDN',
          'Access-Control-Allow-Origin': '*',
        },
      });
    } catch (err) {
      return new Response('Service Unavailable', { status: 502 });
    }
  },
};
