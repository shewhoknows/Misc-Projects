import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type SubmittedAnswer = {
  question_id: string;
  selected_option: "A" | "B" | "C" | "D" | null;
  answer_ms: number;
};

type SubmitBody = {
  match_id: string;
  answers: SubmittedAnswer[];
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return json({ error: "Server is missing Supabase function secrets." }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const authedClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: userData, error: userError } = await authedClient.auth.getUser();
    if (userError || !userData.user) {
      return json({ error: "Sign in before submitting answers." }, 401);
    }
    const userID = userData.user.id;

    const body = (await req.json()) as SubmitBody;
    if (!body.match_id || !Array.isArray(body.answers) || body.answers.length === 0) {
      return json({ error: "Missing match answers." }, 400);
    }

    const { data: playerRow, error: playerError } = await adminClient
      .from("match_players")
      .select("id,match_id,user_id,player_slot,score,correct_count,avg_answer_ms,best_streak,xp_gained,completed_at")
      .eq("match_id", body.match_id)
      .eq("user_id", userID)
      .maybeSingle();
    if (playerError) throw playerError;
    if (!playerRow) {
      return json({ error: "You are not a participant in this match." }, 403);
    }
    if (playerRow.completed_at) {
      return json({ error: "This round was already submitted." }, 409);
    }

    const submittedByQuestion = new Map(body.answers.map((answer) => [answer.question_id, answer]));
    const questionIDs = body.answers.map((answer) => answer.question_id);

    // Pull the match's fixed question set with question_index so that streak
    // scoring is computed in the canonical on-screen order. Without this the
    // questions table query below could return rows in an arbitrary order and
    // make the streak bonus non-deterministic.
    const { data: matchQuestions, error: matchQuestionError } = await adminClient
      .from("match_questions")
      .select("question_id,question_index")
      .eq("match_id", body.match_id)
      .order("question_index", { ascending: true });
    if (matchQuestionError) throw matchQuestionError;
    const allowedQuestionIDs = new Set((matchQuestions ?? []).map((row) => row.question_id));
    if (questionIDs.some((questionID) => !allowedQuestionIDs.has(questionID))) {
      return json({ error: "Submitted answers do not belong to this match." }, 400);
    }

    const { data: questions, error: questionError } = await adminClient
      .from("questions")
      .select("id,topic_id,correct_option")
      .in("id", questionIDs)
      .eq("status", "approved");
    if (questionError) throw questionError;
    if (!questions || questions.length !== questionIDs.length) {
      return json({ error: "Some submitted questions are invalid." }, 400);
    }

    // Build an ordered scoring list: match_questions.question_index -> question.
    const indexByQuestionID = new Map(
      (matchQuestions ?? []).map((row) => [row.question_id, row.question_index]),
    );
    const orderedQuestions = [...questions].sort(
      (a, b) => (indexByQuestionID.get(a.id) ?? 0) - (indexByQuestionID.get(b.id) ?? 0),
    );

    let score = 0;
    let correctCount = 0;
    let currentStreak = 0;
    let bestStreak = 0;
    let totalAnswerMS = 0;
    const answerRows = orderedQuestions.map((question) => {
      const submitted = submittedByQuestion.get(question.id)!;
      const isCorrect = submitted.selected_option === question.correct_option;
      currentStreak = isCorrect ? currentStreak + 1 : 0;
      bestStreak = Math.max(bestStreak, currentStreak);
      const answerMS = Math.max(0, Math.min(10000, Math.round(submitted.answer_ms)));
      totalAnswerMS += answerMS;
      const points = isCorrect ? 100 + Math.floor(((10000 - answerMS) / 10000) * 50) + (currentStreak >= 3 ? 25 : 0) : 0;
      if (isCorrect) correctCount += 1;
      score += points;
      return {
        match_id: body.match_id,
        user_id: userID,
        question_id: question.id,
        selected_option: submitted.selected_option,
        is_correct: isCorrect,
        answer_ms: answerMS,
        points,
      };
    });

    const xpGained = correctCount === questions.length ? 170 : 60 + correctCount * 10;
    const completedAt = new Date().toISOString();

    const { error: answersError } = await adminClient
      .from("player_answers")
      .upsert(answerRows, { onConflict: "match_id,user_id,question_id" });
    if (answersError) throw answersError;

    const { data: updatedPlayers, error: updatePlayerError } = await adminClient
      .from("match_players")
      .update({
        score,
        correct_count: correctCount,
        avg_answer_ms: Math.round(totalAnswerMS / questions.length),
        best_streak: bestStreak,
        xp_gained: xpGained,
        completed_at: completedAt,
      })
      .eq("match_id", body.match_id)
      .eq("user_id", userID)
      .select("id,match_id,user_id,player_slot,score,correct_count,avg_answer_ms,best_streak,xp_gained,completed_at");
    if (updatePlayerError) throw updatePlayerError;

    const player = updatedPlayers?.[0];
    if (!player) return json({ error: "Could not update player result." }, 500);

    const { data: allPlayers, error: playersError } = await adminClient
      .from("match_players")
      .select("id,match_id,user_id,player_slot,score,correct_count,avg_answer_ms,best_streak,xp_gained,completed_at")
      .eq("match_id", body.match_id);
    if (playersError) throw playersError;

    const completedPlayers = (allPlayers ?? []).filter((row) => row.completed_at);
    let matchStatus = completedPlayers.length >= 2 ? "completed" : "waiting";
    let winnerID: string | null = null;
    if (completedPlayers.length >= 2) {
      const winner = completedPlayers.reduce((best, row) => (row.score > best.score ? row : best), completedPlayers[0]);
      winnerID = winner.user_id;
    }

    const { data: updatedMatches, error: matchUpdateError } = await adminClient
      .from("matches")
      .update({
        status: matchStatus,
        winner_id: winnerID,
        completed_at: matchStatus === "completed" ? completedAt : null,
      })
      .eq("id", body.match_id)
      .select("id,topic_id,match_type,status,created_by,winner_id,created_at,completed_at");
    if (matchUpdateError) throw matchUpdateError;

    const match = updatedMatches?.[0];
    if (match?.topic_id) {
      await updateTopicStats(adminClient, userID, match.topic_id, score, correctCount, questions.length, xpGained, winnerID);
      const { data: profile } = await adminClient
        .from("profiles")
        .select("total_xp")
        .eq("id", userID)
        .maybeSingle();
      await adminClient
        .from("profiles")
        .update({ total_xp: (profile?.total_xp ?? 0) + xpGained, updated_at: completedAt })
        .eq("id", userID);
    }

    return json({
      match,
      player,
      opponent: (allPlayers ?? []).find((row) => row.user_id !== userID) ?? null,
      answers: answerRows,
    });
  } catch (error) {
    console.error(error);
    return json({ error: "Could not submit match answers." }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

async function updateTopicStats(
  client: ReturnType<typeof createClient>,
  userID: string,
  topicID: string,
  score: number,
  correctCount: number,
  totalAnswers: number,
  xpGained: number,
  winnerID: string | null,
) {
  const { data: existing } = await client
    .from("topic_user_stats")
    .select("id,xp,wins,losses,matches_played,best_score,correct_answers,total_answers")
    .eq("user_id", userID)
    .eq("topic_id", topicID)
    .maybeSingle();

  const isWin = winnerID === userID;
  const next = {
    user_id: userID,
    topic_id: topicID,
    xp: (existing?.xp ?? 0) + xpGained,
    wins: (existing?.wins ?? 0) + (winnerID ? (isWin ? 1 : 0) : 0),
    losses: (existing?.losses ?? 0) + (winnerID ? (isWin ? 0 : 1) : 0),
    matches_played: (existing?.matches_played ?? 0) + 1,
    best_score: Math.max(existing?.best_score ?? 0, score),
    correct_answers: (existing?.correct_answers ?? 0) + correctCount,
    total_answers: (existing?.total_answers ?? 0) + totalAnswers,
    updated_at: new Date().toISOString(),
  };

  await client
    .from("topic_user_stats")
    .upsert(next, { onConflict: "user_id,topic_id" });
}
