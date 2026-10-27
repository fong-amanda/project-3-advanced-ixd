import { team, people } from "./iterations.js";

function Card({ title, description, href }) {
  const pending = !href || href === "#";
  return (
    <a
      className={pending ? "card pending" : "card"}
      href={pending ? undefined : href}
      target={pending ? undefined : "_blank"}
      rel="noopener noreferrer"
      aria-disabled={pending || undefined}
    >
      <span>
        {title}
        {description && <small>{description}</small>}
      </span>
      <span className="arrow" aria-hidden="true">
        ↗{pending && <em>Link coming</em>}
      </span>
    </a>
  );
}

function Section({ name, color, items, isTeam }) {
  return (
    <section
      className={isTeam ? "team" : undefined}
      style={{ "--c": `var(--${color})`, "--cs": `var(--${color}-soft)` }}
    >
      <div className="sechead">
        {!isTeam && (
          <span className="initial" aria-hidden="true">
            {name[0]}
          </span>
        )}
        <h2>{name}</h2>
      </div>
      <div className="cards">
        {items.map((item, i) => (
          <Card key={item.title + i} {...item} />
        ))}
      </div>
    </section>
  );
}

export default function App() {
  return (
    <div className="wrap">
      <header className="page">
        <span className="course">AIxD Project 3: Zero to Launch</span>
        <h1>Our iterations</h1>
      </header>
      <Section
        name="Team prototype"
        color="team"
        items={team.iterations}
        isTeam
      />{" "}
      {people.map((p) => (
        <Section
          key={p.name}
          name={p.name}
          color={p.color}
          items={p.iterations}
        />
      ))}
    </div>
  );
}
