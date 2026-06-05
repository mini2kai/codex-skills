import React from 'react';
import { createRoot } from 'react-dom/client';
import { ArrowRight, Check, ExternalLink, Gauge, Layers, Shield } from 'lucide-react';
import './styles.css';

const features = [
  { icon: Layers, title: '清晰结构', text: '把复杂方案拆成首页、能力、流程和交付物，方便第一眼理解。' },
  { icon: Gauge, title: '快速预览', text: '默认发布到 localhost:9999，先确认本地可运行，再处理外网分享。' },
  { icon: Shield, title: '稳妥交付', text: '把模板当起点，按 DESIGN.md 和本轮要求改成真实可用页面。' },
];

function App() {
  return (
    <main>
      <section className="hero">
        <nav className="nav" aria-label="主导航">
          <strong>Demo Studio</strong>
          <a href="#details">Details</a>
        </nav>
        <div className="heroGrid">
          <div>
            <p className="eyebrow">Runnable web demo</p>
            <h1>把想法变成可以分享的网页演示</h1>
            <p className="lead">这是一个产品介绍页起点。请替换为用户的产品名、核心卖点、真实数据和适合受众的语言。</p>
            <div className="actions">
              <a className="primary" href="#details">查看内容 <ArrowRight size={18} /></a>
              <a className="secondary" href="http://localhost:9999/" target="_blank" rel="noreferrer">本地预览 <ExternalLink size={17} /></a>
            </div>
          </div>
          <div className="panel" aria-label="交付状态">
            <span>Preview pipeline</span>
            <ol>
              <li><Check size={16} /> 生成页面结构</li>
              <li><Check size={16} /> 构建静态资源</li>
              <li><Check size={16} /> 发布到 9999</li>
            </ol>
          </div>
        </div>
      </section>

      <section id="details" className="band">
        <div className="sectionHead">
          <p className="eyebrow">What to adapt</p>
          <h2>把模板改成真实业务页面</h2>
        </div>
        <div className="features">
          {features.map((item) => {
            const Icon = item.icon;
            return (
              <article className="feature" key={item.title}>
                <Icon size={22} />
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </article>
            );
          })}
        </div>
      </section>
    </main>
  );
}

createRoot(document.getElementById('root')).render(<App />);

