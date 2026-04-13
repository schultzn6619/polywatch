import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { Shield, KeyRound, AtSign } from "lucide-react";

export default function LoginPage() {
  const [isLogin, setIsLogin] = useState(true);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    setTimeout(() => {
      if (email && password) {
        localStorage.setItem("polywatch_user", email);
        navigate("/dashboard");
      } else {
        setError("Please enter your credentials");
      }
      setLoading(false);
    }, 600);
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center px-6">
      {/* Brand */}
      <div className="mb-8 text-center">
        <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/15 border border-primary/30">
          <Shield className="h-7 w-7 text-primary" />
        </div>
        <h1 className="text-xl font-bold tracking-widest uppercase">PolyWatch</h1>
        <p className="mt-1 text-xs tracking-[0.2em] uppercase text-muted-foreground">
          Insider Intelligence System
        </p>
      </div>

      {/* Form card */}
      <div className="w-full max-w-sm rounded-2xl border border-border bg-card p-7 shadow-lg">
        <h2 className="text-xl font-semibold">
          {isLogin ? "Welcome back" : "Create account"}
        </h2>
        <p className="mt-1 text-sm text-muted-foreground">
          {isLogin ? "Sign in to continue to your dashboard" : "Initialize your terminal access"}
        </p>

        {error && (
          <div className="mt-4 rounded-lg bg-destructive/10 px-4 py-2.5 text-sm text-destructive">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="mt-6 space-y-5">
          <div>
            <label className="mb-1.5 block text-xs font-semibold tracking-wider uppercase text-muted-foreground">
              Terminal ID
            </label>
            <div className="relative">
              <AtSign className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <input
                type="text"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="Enter your email"
                required
                autoComplete="username"
                className="w-full rounded-xl border border-border bg-surface pl-10 pr-4 py-3 text-sm text-foreground placeholder:text-muted-foreground outline-none transition-colors focus:border-primary"
              />
            </div>
          </div>
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="block text-xs font-semibold tracking-wider uppercase text-muted-foreground">
                Access Key
              </label>
              {isLogin && (
                <button type="button" className="text-xs font-semibold text-primary hover:text-primary-dark transition-colors">
                  Forgot key?
                </button>
              )}
            </div>
            <div className="relative">
              <KeyRound className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                autoComplete="current-password"
                className="w-full rounded-xl border border-border bg-surface pl-10 pr-4 py-3 text-sm text-foreground placeholder:text-muted-foreground outline-none transition-colors focus:border-primary"
              />
            </div>
          </div>

          {isLogin && (
            <label className="flex items-center gap-2 text-sm text-muted-foreground cursor-pointer">
              <input type="checkbox" className="rounded border-border accent-primary" />
              Maintain persistent session
            </label>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-xl bg-primary py-3 text-sm font-bold tracking-wider uppercase text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)] disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {loading
              ? "Initializing..."
              : isLogin
                ? "Initialize Session"
                : "Create Terminal"}
          </button>
        </form>

        <div className="mt-5 text-center text-sm text-muted-foreground">
          {isLogin ? "Don't have an account? " : "Already have an account? "}
          <button
            type="button"
            onClick={() => {
              setIsLogin(!isLogin);
              setError("");
            }}
            className="font-semibold text-primary transition-colors hover:text-primary-dark"
          >
            {isLogin ? "Sign up" : "Sign in"}
          </button>
        </div>
      </div>

      {/* Footer */}
      <div className="mt-8 flex flex-wrap items-center justify-center gap-4 text-xs text-muted-foreground">
        <span>&copy; 2024 PolyWatch AI. Insider Intelligence System</span>
        <a href="#" className="hover:text-primary transition-colors">Security Protocol</a>
        <a href="#" className="hover:text-primary transition-colors">Privacy Policy</a>
        <a href="#" className="hover:text-primary transition-colors">Terms of Service</a>
      </div>
    </div>
  );
}
