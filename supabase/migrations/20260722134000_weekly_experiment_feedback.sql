alter table public.weekly_experiments
    add column if not exists user_feedback text,
    add column if not exists feedback_note text,
    add column if not exists feedback_submitted_at timestamptz;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'weekly_experiments_user_feedback_check'
          and conrelid = 'public.weekly_experiments'::regclass
    ) then
        alter table public.weekly_experiments
            add constraint weekly_experiments_user_feedback_check
            check (user_feedback is null or user_feedback in ('helpful', 'neutral', 'not_helpful'));
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'weekly_experiments_feedback_note_length_check'
          and conrelid = 'public.weekly_experiments'::regclass
    ) then
        alter table public.weekly_experiments
            add constraint weekly_experiments_feedback_note_length_check
            check (feedback_note is null or char_length(feedback_note) <= 500);
    end if;
end $$;
