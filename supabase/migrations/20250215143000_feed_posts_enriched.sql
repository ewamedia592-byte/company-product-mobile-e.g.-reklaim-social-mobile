begin;

drop view if exists public.feed_posts_enriched;

-- Ensure moderation metadata columns exist before referencing them in the view.
alter table public.public_profiles
  add column if not exists quality_publish_score numeric(5, 2),
  add column if not exists quality_engagement_rate numeric(5, 2),
  add column if not exists quality_moderation_strike_count smallint,
  add column if not exists quality_endorsement_total integer,
  add column if not exists quality_badge text not null default 'none',
  add column if not exists quality_metrics_refreshed_at timestamptz;

update public.public_profiles
   set quality_badge = coalesce(quality_badge, 'none');

create view public.feed_posts_enriched as
select
    p.id,
    p.user_id,
    p.category,
    p.content,
    p.media_url,
    p.filter_used,
    p.created_at,
    jsonb_build_object(
        'id', pp.id,
        'username', coalesce(pp.username, 'Anonymous'),
        'avatarUrl', pp.avatar_url,
        'bio', pp.bio,
        'isBusiness', coalesce(pp.is_business, false),
        'followersCount', pp.followers_count,
        'followingCount', pp.following_count,
        'moderation', jsonb_build_object(
            'qualityBadge', coalesce(pp.quality_badge, 'none'),
            'qualityPublishScore', pp.quality_publish_score,
            'qualityEngagementRate', pp.quality_engagement_rate,
            'qualityModerationStrikes', pp.quality_moderation_strike_count,
            'qualityEndorsementTotal', pp.quality_endorsement_total,
            'qualityMetricsRefreshedAt', pp.quality_metrics_refreshed_at,
            'trustScore', ap.trust_score,
            'trustLevel', ap.level,
            'positiveInteractionRate', ap.positive_interaction_rate,
            'verificationFlags', coalesce(
                to_jsonb(array_remove(array[
                    case
                        when coalesce(pp.parent_consent_status, 'not_required') = 'approved'
                            then 'parent-approved'
                    end,
                    case when coalesce(pp.is_business, false) then 'business-account' end,
                    case when coalesce(pp.is_minor, false) then 'minor-protected' end,
                    case when coalesce(pp.quality_moderation_strike_count, 0) = 0
                        then 'clean-record'
                    end,
                    case when coalesce(ap.trust_score, 0) >= 80 then 'high-trust' end
                ], null)),
                '[]'::jsonb
            )
        )
    ) as author_profile
from public.posts p
left join public.public_profiles pp
  on pp.id = p.user_id
left join public.amplify_profiles ap
  on ap.user_id = p.user_id;

grant select on public.feed_posts_enriched to authenticated, anon;

commit;
