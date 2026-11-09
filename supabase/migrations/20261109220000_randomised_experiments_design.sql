-- Randomised experiments: Corva picks the ON nights and stores them as the experiment's tags.
-- (20261109215857_randomised_experiments.sql is empty: it was created by mistake and was
-- already recorded as applied, so this change lives here.)
alter table public.experiments drop constraint experiments_design_check;
alter table public.experiments add constraint experiments_design_check
  check (design in ('beforeAfter', 'onOff', 'randomised'));
