import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { Eye } from "lucide-react";

export default function LoginPage() {
  const [isLogin, setIsLogin] = useState(true);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    // Simulated auth — replace with real API
    setTimeout(() => {
      if (username && password) {
        localStorage.setItem("polywatch_user", username);
        navigate("/dashboard");
      } else {
        setError("Please enter username and password");
      }
      setLoading(false);
    }, 600);
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-6 pt-16">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10">
            <Eye className="h-6 w-6 text-primary" />
          </div>
          <h1 className="text-2xl font-bold">
            {isLogin ? "Welcome back" : "Create account"}
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {isLogin ? "Sign in to continue" : "Get started for free"}
          </p>
        </div>

        <div className="rounded-xl border border-border bg-card p-6">
          {error && (
            <div className="mb-5 rounded-lg bg-destructive/10 px-4 py-2.5 text-sm text-destructive">
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="mb-1.5 block text-sm font-medium text-foreground">
                Username
              </label>
              <input
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="Enter your username"
                required
                autoComplete="username"
                className="w-full rounded-xl border border-border bg-surface px-4 py-2.5 text-sm text-foreground placeholder:text-muted-foreground outline-none transition-colors focus:border-primary"
              />
            </div>
            <div>
              <label className="mb-1.5 block text-sm font-medium text-foreground">
                Password
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                autoComplete="current-password"
                className="w-full rounded-xl border border-border bg-surface px-4 py-2.5 text-sm text-foreground placeholder:text-muted-foreground outline-none transition-colors focus:border-primary"
              />
            </div>
            <button
              type="submit"
              disabled={loading}
              className="w-full rounded-xl bg-primary py-3 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)] disabled:opacity-40 disabled:cursor-not-allowed"
            >
              {loading
                ? isLogin
                  ? "Signing in..."
                  : "Signing up..."
                : isLogin
                  ? "Sign in"
                  : "Sign up"}
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
              className="font-medium text-primary transition-colors hover:text-primary-dark"
            >
              {isLogin ? "Sign up" : "Sign in"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
