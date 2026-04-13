import { Link } from "react-router-dom";
import {
  Brain,
  Wrench,
  Activity,
  Shield,
  Search,
  Network,
  ArrowRight,
  ChevronRight,
} from "lucide-react";
import { features, steps, toolCategories, stats } from "../data/mockData";

const iconMap: Record<string, React.ElementType> = {
  Brain, Wrench, Activity, Shield, Search, Network,
};

export default function LandingPage() {
  return (
    <div className="min-h-screen">
      {/* Hero */}
      <section className="relative flex min-h-[90vh] flex-col items-center justify-center px-6 pt-24 text-center">
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,rgba(245,158,11,0.08)_0%,transparent_60%)]" />
        <div className="relative z-10 mx-auto max-w-3xl">
          <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-border bg-card px-4 py-1.5 text-xs text-muted-foreground">
            <span className="h-1.5 w-1.5 rounded-full bg-success" />
            AI-Powered Market Intelligence
          </div>
          <h1 className="text-4xl font-bold leading-tight tracking-tight sm:text-5xl lg:text-6xl">
            Uncover Insider Trading on{" "}
            <span className="text-primary">Polymarket</span>
          </h1>
          <p className="mx-auto mt-6 max-w-xl text-lg leading-relaxed text-muted-foreground">
            PolyWatch uses Tree of Thought AI to automatically analyze trading
            patterns, detect suspicious activity, and generate evidence-based
            investigation reports.
          </p>
          <div className="mt-8 flex flex-col items-center gap-4 sm:flex-row sm:justify-center">
            <Link
              to="/login"
              className="inline-flex items-center gap-2 rounded-xl bg-primary px-6 py-3 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)]"
            >
              Start Investigating <ArrowRight className="h-4 w-4" />
            </Link>
            <a
              href="#how-it-works"
              className="inline-flex items-center gap-2 rounded-xl border border-border px-6 py-3 text-sm font-medium text-foreground transition-colors hover:border-primary/30 hover:bg-muted"
            >
              See How It Works <ChevronRight className="h-4 w-4" />
            </a>
          </div>
        </div>

        {/* Stats bar */}
        <div className="relative z-10 mx-auto mt-20 grid w-full max-w-2xl grid-cols-2 gap-4 sm:grid-cols-4">
          {stats.map((s) => (
            <div key={s.label} className="rounded-xl border border-border bg-card p-4 text-center">
              <div className="text-2xl font-bold text-primary">{s.value}</div>
              <div className="mt-1 text-xs text-muted-foreground">{s.label}</div>
            </div>
          ))}
        </div>
      </section>

      {/* Features */}
      <section id="features" className="px-6 py-24">
        <div className="mx-auto max-w-6xl">
          <div className="mb-12 text-center">
            <h2 className="text-3xl font-bold">Powerful Investigation Engine</h2>
            <p className="mx-auto mt-3 max-w-lg text-muted-foreground">
              26 automated tools across 5 categories, orchestrated by recursive
              AI reasoning.
            </p>
          </div>
          <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {features.map((f) => {
              const Icon = iconMap[f.icon];
              return (
                <div
                  key={f.title}
                  className="group rounded-xl border border-border bg-card p-6 transition-all hover:border-primary/20 hover:shadow-[0_0_20px_rgba(245,158,11,0.1)]"
                >
                  <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                    <Icon className="h-5 w-5 text-primary" />
                  </div>
                  <h3 className="text-lg font-semibold">{f.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                    {f.description}
                  </p>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* How it works */}
      <section id="how-it-works" className="border-t border-border bg-surface px-6 py-24">
        <div className="mx-auto max-w-4xl">
          <div className="mb-12 text-center">
            <h2 className="text-3xl font-bold">How It Works</h2>
            <p className="mx-auto mt-3 max-w-lg text-muted-foreground">
              From search to evidence-based report in four simple steps.
            </p>
          </div>
          <div className="grid gap-8 sm:grid-cols-2">
            {steps.map((s) => (
              <div key={s.number} className="flex gap-4">
                <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-lg font-bold text-primary">
                  {s.number}
                </div>
                <div>
                  <h3 className="text-lg font-semibold">{s.title}</h3>
                  <p className="mt-1 text-sm leading-relaxed text-muted-foreground">
                    {s.description}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Tools */}
      <section id="tools" className="px-6 py-24">
        <div className="mx-auto max-w-4xl">
          <div className="mb-12 text-center">
            <h2 className="text-3xl font-bold">Investigation Toolkit</h2>
            <p className="mx-auto mt-3 max-w-lg text-muted-foreground">
              Five specialized categories of tools working together to surface
              the truth.
            </p>
          </div>
          <div className="space-y-4">
            {toolCategories.map((c) => (
              <div
                key={c.name}
                className="rounded-xl border border-border bg-card p-5 transition-all hover:border-primary/20"
              >
                <div className="flex items-center justify-between">
                  <h3 className="font-semibold">{c.name}</h3>
                  <span className="rounded-full bg-primary/10 px-3 py-0.5 text-xs font-medium text-primary">
                    {c.count} tools
                  </span>
                </div>
                <div className="mt-3 flex flex-wrap gap-2">
                  {c.examples.map((e) => (
                    <span
                      key={e}
                      className="rounded-lg bg-muted px-3 py-1 text-xs text-muted-foreground"
                    >
                      {e}
                    </span>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="border-t border-border bg-surface px-6 py-24">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-bold">Ready to Investigate?</h2>
          <p className="mx-auto mt-3 max-w-lg text-muted-foreground">
            Start uncovering suspicious trading patterns on Polymarket with
            AI-powered forensic analysis.
          </p>
          <Link
            to="/login"
            className="mt-8 inline-flex items-center gap-2 rounded-xl bg-primary px-8 py-3.5 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)]"
          >
            Get Started Free <ArrowRight className="h-4 w-4" />
          </Link>
        </div>
      </section>
    </div>
  );
}
