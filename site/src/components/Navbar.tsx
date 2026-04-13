import { useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { Menu, X, Eye } from "lucide-react";
import { navLinks } from "../data/mockData";

export default function Navbar() {
  const [open, setOpen] = useState(false);
  const location = useLocation();
  const isLanding = location.pathname === "/";

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 border-b border-border bg-background/80 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
        <Link to="/" className="flex items-center gap-2 text-lg font-bold text-foreground">
          <Eye className="h-5 w-5 text-primary" />
          PolyWatch
        </Link>

        {/* Desktop */}
        <div className="hidden items-center gap-8 md:flex">
          {isLanding &&
            navLinks.map((l) => (
              <a
                key={l.href}
                href={l.href}
                className="text-sm text-muted-foreground transition-colors hover:text-primary"
              >
                {l.label}
              </a>
            ))}
          <Link
            to="/login"
            className="text-sm text-muted-foreground transition-colors hover:text-primary"
          >
            Sign in
          </Link>
          <Link
            to="/login"
            className="inline-flex items-center justify-center rounded-xl bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)]"
          >
            Get Started
          </Link>
        </div>

        {/* Mobile toggle */}
        <button
          className="text-foreground md:hidden"
          onClick={() => setOpen(!open)}
          aria-label="Toggle menu"
        >
          {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </div>

      {/* Mobile menu */}
      {open && (
        <div className="border-t border-border bg-background px-6 py-4 md:hidden">
          <div className="flex flex-col gap-4">
            {isLanding &&
              navLinks.map((l) => (
                <a
                  key={l.href}
                  href={l.href}
                  className="text-sm text-muted-foreground"
                  onClick={() => setOpen(false)}
                >
                  {l.label}
                </a>
              ))}
            <Link to="/login" className="text-sm text-muted-foreground" onClick={() => setOpen(false)}>
              Sign in
            </Link>
            <Link
              to="/login"
              className="inline-flex items-center justify-center rounded-xl bg-primary px-5 py-2.5 text-sm font-semibold text-primary-foreground"
              onClick={() => setOpen(false)}
            >
              Get Started
            </Link>
          </div>
        </div>
      )}
    </nav>
  );
}
