// ============================================================
// EXPLAIN_A · Gemini 프록시 (Supabase Edge Function)
// Gemini API 키를 클라이언트에 노출하지 않고 서버에서만 사용한다.
// 시크릿 이름: GEMINI_API_KEY
//
// 배포(대시보드): Edge Functions → Deploy a new function →
//   이름 "gemini-proxy" → 아래 코드 전체 붙여넣기 → Deploy
// 시크릿: Edge Functions → Secrets → GEMINI_API_KEY 추가
// ============================================================

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const KEY = Deno.env.get("GEMINI_API_KEY");
    if (!KEY) {
      return json({ error: "GEMINI_API_KEY 시크릿이 설정되지 않았습니다." }, 500);
    }

    // 클라이언트는 { parts, json, model } 만 보낸다 (Gemini 요청 형태는 서버가 구성)
    const { parts, json: wantJson, model } = await req.json();
    if (!Array.isArray(parts)) return json({ error: "parts 배열이 필요합니다." }, 400);

    const m = model || "gemini-2.5-flash";
    const body: Record<string, unknown> = { contents: [{ role: "user", parts }] };
    if (wantJson) body.generationConfig = { responseMimeType: "application/json", temperature: 0.4 };

    const r = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent?key=${KEY}`,
      { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) },
    );

    const data = await r.json();
    if (!r.ok) return json({ error: "Gemini " + r.status, detail: data }, r.status);

    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    return json({ text });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
