// The second idea: the distance it is used across. A map with no borders, only its lines of latitude and longitude and
// a few cities: you in Shanghai, on the move; your machine in Beijing, at the office; a line straight between them.
import * as css from "./site.css.ts";
import { APP, Button, Demo, type DemoProps } from "./Site.tsx";

/** Where a place is drawn: longitude 112.5°E to 126.5°E across, latitude 42°N to 29°N down. */
const at = (lon: number, lat: number) => ({ x: (lon - 112.5) * 40, y: (42 - lat) * 49 });

const MACHINE = at(116.4, 39.9);
const YOU = at(121.47, 31.23);
/** The way between them: a little bowed, as a long line on a map looks. */
const BEND = { x: 230, y: 330 };
const ROUTE = `M${MACHINE.x} ${MACHINE.y} Q${BEND.x} ${BEND.y} ${YOU.x} ${YOU.y}`;
const BACK = `M${YOU.x} ${YOU.y} Q${BEND.x} ${BEND.y} ${MACHINE.x} ${MACHINE.y}`;
const MID = { x: 0.25 * MACHINE.x + 0.5 * BEND.x + 0.25 * YOU.x, y: 0.25 * MACHINE.y + 0.5 * BEND.y + 0.25 * YOU.y };

/** Other cities, to place the two on the map. */
const CITIES = [
  { name: "天津", ...at(117.2, 39.13) },
  { name: "济南", ...at(117.0, 36.65) },
  { name: "青岛", ...at(120.38, 36.07) },
  { name: "徐州", ...at(117.18, 34.26) },
  { name: "合肥", ...at(117.27, 31.86) },
  { name: "南京", ...at(118.8, 32.06) },
];

function MapPicture() {
  const lons = Array.from({ length: 14 }, (_, i) => 113 + i);
  const lats = Array.from({ length: 12 }, (_, i) => 30 + i);
  return (
    <svg className={css.map} viewBox="0 0 560 640" role="img" aria-label="上海的手机与北京的电脑 Studio 点对点连接，直线距离约 1,068 公里">
      {lons.map((lon) => <line key={lon} className={css.mapGrid} x1={at(lon, 0).x} x2={at(lon, 0).x} y1={0} y2={640} />)}
      {lats.map((lat) => <line key={lat} className={css.mapGrid} x1={0} x2={560} y1={at(0, lat).y} y2={at(0, lat).y} />)}
      {lons.filter((lon) => lon % 2 === 0).map((lon) => <text key={lon} className={css.mapDegree} x={at(lon, 0).x + 4} y={632}>{lon}°E</text>)}
      {lats.filter((lat) => lat % 2 === 0).map((lat) => <text key={lat} className={css.mapDegree} x={4} y={at(0, lat).y - 4}>{lat}°N</text>)}
      {CITIES.map((c) => (
        <g key={c.name} className={css.mapCity}>
          <circle cx={c.x} cy={c.y} r={3} />
          <text x={c.x + 8} y={c.y} dominantBaseline="central">{c.name}</text>
        </g>
      ))}

      <path className={css.mapRoute} d={ROUTE} />
      {/* What goes each way along it (not where less motion is asked for: site.css.ts). */}
      <circle className={css.pulse} r={4}><animateMotion dur="2.4s" repeatCount="indefinite" path={ROUTE} /></circle>
      <circle className={css.pulse} r={4}><animateMotion dur="2.4s" begin="1.2s" repeatCount="indefinite" path={BACK} /></circle>
      <g className={css.mapLink}>
        <rect x={MID.x - 66} y={MID.y - 24} width={132} height={48} rx={24} />
        <text className={css.mapLinkMain} x={MID.x} y={MID.y - 7} textAnchor="middle" dominantBaseline="central">点对点 · 38 ms</text>
        <text className={css.mapLinkSub} x={MID.x} y={MID.y + 11} textAnchor="middle" dominantBaseline="central">1,068 km</text>
      </g>

      <circle className={css.mapHalo} cx={MACHINE.x} cy={MACHINE.y} r={14} />
      <circle className={css.mapSpot} cx={MACHINE.x} cy={MACHINE.y} r={6} />
      <g className={css.mapCard}>
        <rect x={MACHINE.x + 22} y={MACHINE.y - 64} width={176} height={74} rx={14} />
        <circle className={css.onlineSpot} cx={MACHINE.x + 44} cy={MACHINE.y - 38} r={4} />
        <text className={css.mapCardMain} x={MACHINE.x + 56} y={MACHINE.y - 38} dominantBaseline="central">Studio · 在线</text>
        <text className={css.mapCardSub} x={MACHINE.x + 40} y={MACHINE.y - 14} dominantBaseline="central">北京</text>
      </g>

      <circle className={css.mapHalo} cx={YOU.x} cy={YOU.y} r={14} />
      <circle className={css.mapSpot} cx={YOU.x} cy={YOU.y} r={6} />
      <g className={css.mapCard}>
        <rect x={YOU.x - 140} y={YOU.y + 18} width={160} height={74} rx={14} />
        <text className={css.mapCardMain} x={YOU.x - 122} y={YOU.y + 44} dominantBaseline="central">你的手机</text>
        <text className={css.mapCardSub} x={YOU.x - 122} y={YOU.y + 68} dominantBaseline="central">上海</text>
      </g>
    </svg>
  );
}

/** What makes the distance not matter. */
const POINTS = [
  { title: "点对点连接", text: "设备之间直接连接，无法直连时经加密中继转发" },
  { title: "数据保存在你的电脑上", text: "对话、文件和记录保存在你的电脑上，云端只负责账号" },
  { title: "多端使用", text: "桌面 app、网页、Android、Slack 和飞书" },
];

export function Distance(props: DemoProps) {
  return (
    <>
      <header className={css.hero}>
        <div className={`${css.wrap} ${css.heroRow}`}>
          <div className={css.heroWords}>
            <h1 className={css.title}><span className={css.phrase}>设备与电脑</span><span className={css.phrase}>点对点连接</span></h1>
            <p className={css.lede}>手机和电脑通过点对点连接访问你的电脑，无法直连时经加密中继转发。对话和文件保存在你的电脑上，不存储在云端。</p>
            <div className={css.heroActions}>
              <Button href={APP} kind="primary" large>开始使用</Button>
              <span className={css.heroNote}>示意：北京—上海直线距离约 1,068 km</span>
            </div>
          </div>
          <div className={css.pictureBox}><MapPicture /></div>
        </div>
      </header>

      <section className={css.section}>
        <div className={css.wrap}>
          <ol className={css.links}>
            {POINTS.map((p, i) => (
              <li key={p.title} className={css.link}>
                <span className={css.linkNumber}>{String(i + 1).padStart(2, "0")}</span>
                <h3 className={css.linkTitle}>{p.title}</h3>
                <p className={css.linkText}>{p.text}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className={css.section}>
        <div className={css.wrap}>
          <h2 className={css.headingTitle}>试用 still.fail</h2>
          <p className={css.headingLede}>以下为使用示例数据的 still.fail</p>
          <div className={`${css.edge} ${css.demoAfterHeading}`}>
            <Demo v="2" {...(props.mountDemo ? { mount: props.mountDemo } : {})} {...(props.demo ? { frame: props.demo } : {})} />
          </div>
        </div>
      </section>
    </>
  );
}
