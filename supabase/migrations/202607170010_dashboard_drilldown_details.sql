create or replace function public.admin_dashboard_drill_v1(
  p_dimension text,
  p_value text,
  p_filters jsonb default '{}'::jsonb,
  p_search text default ''
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
  v_search text := '%' || btrim(coalesce(p_search, '')) || '%';
  v_summary jsonb;
  v_customers jsonb;
  v_designs jsonb;
begin
  if not public.staff_has_permission(auth.uid(), 'dashboard.view') then
    raise exception 'PERMISSION_DENIED';
  end if;

  if p_dimension not in (
    'designNo',
    'companyName',
    'firm',
    'state',
    'city',
    'agent',
    'category',
    'style',
    'fabric',
    'source'
  ) then
    raise exception 'INVALID_DASHBOARD_DIMENSION';
  end if;

  drop table if exists pg_temp._dashboard_drill_facts;

  create temporary table _dashboard_drill_facts
  on commit drop
  as
  select
    o.id as order_id,
    o.customer_id,
    o.firm,
    o.status,
    o.updated_at,

    i.design_no,
    i.qty as sets,
    i.qty * i.pcs_per_set_snapshot as pieces,

    coalesce(
      nullif(btrim(i.category_snapshot), ''),
      'Not specified'
    ) as category,

    coalesce(
      nullif(btrim(i.style_snapshot), ''),
      'Not specified'
    ) as style,

    coalesce(
      nullif(btrim(i.fabric_snapshot), ''),
      'Not specified'
    ) as fabric,

    coalesce(
      nullif(btrim(i.last_modified_by_type), ''),
      'unknown'
    ) as source,

    c.company_name,
    c.contact_name,
    c.phone_e164,

    coalesce(
      nullif(btrim(c.city), ''),
      'Not specified'
    ) as city,

    coalesce(
      nullif(btrim(c.state), ''),
      'Not specified'
    ) as state,

    coalesce(
      nullif(btrim(c.agent), ''),
      'Not specified'
    ) as agent,

    c.checked_in_at

  from public.order_items i
  join public.orders o
    on o.id = i.order_id
  join public.customers c
    on c.id = o.customer_id

  where
    (
      not (p_filters ? 'firm')
      or o.firm = any(
        select jsonb_array_elements_text(p_filters -> 'firm')
      )
    )

    and (
      not (p_filters ? 'state')
      or coalesce(
        nullif(btrim(c.state), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'state')
      )
    )

    and (
      not (p_filters ? 'city')
      or coalesce(
        nullif(btrim(c.city), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'city')
      )
    )

    and (
      not (p_filters ? 'agent')
      or coalesce(
        nullif(btrim(c.agent), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'agent')
      )
    )

    and (
      not (p_filters ? 'category')
      or coalesce(
        nullif(btrim(i.category_snapshot), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'category')
      )
    )

    and (
      not (p_filters ? 'style')
      or coalesce(
        nullif(btrim(i.style_snapshot), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'style')
      )
    )

    and (
      not (p_filters ? 'fabric')
      or coalesce(
        nullif(btrim(i.fabric_snapshot), ''),
        'Not specified'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'fabric')
      )
    )

    and (
      not (p_filters ? 'designNo')
      or i.design_no = any(
        select jsonb_array_elements_text(p_filters -> 'designNo')
      )
    )

    and (
      not (p_filters ? 'companyName')
      or c.company_name = any(
        select jsonb_array_elements_text(
          p_filters -> 'companyName'
        )
      )
    )

    and (
      not (p_filters ? 'status')
      or o.status = any(
        select jsonb_array_elements_text(p_filters -> 'status')
      )
    )

    and (
      not (p_filters ? 'source')
      or coalesce(
        nullif(btrim(i.last_modified_by_type), ''),
        'unknown'
      ) = any(
        select jsonb_array_elements_text(p_filters -> 'source')
      )
    )

    and (
      not (p_filters ? 'checkedIn')
      or (
        case
          when c.checked_in_at is null then 'No'
          else 'Yes'
        end
      ) = any(
        select jsonb_array_elements_text(
          p_filters -> 'checkedIn'
        )
      )
    )

    and (
      not (p_filters ? 'dateFrom')
      or o.updated_at >=
        ((p_filters -> 'dateFrom' ->> 0)::date)::timestamptz
    )

    and (
      not (p_filters ? 'dateTo')
      or o.updated_at <
        (
          ((p_filters -> 'dateTo' ->> 0)::date + 1)
        )::timestamptz
    )

    and (
      btrim(coalesce(p_search, '')) = ''
      or c.company_name ilike v_search
      or c.contact_name ilike v_search
      or c.phone_e164 ilike v_search
      or i.design_no ilike v_search
    )

    and (
      case p_dimension
        when 'designNo' then
          i.design_no = p_value

        when 'companyName' then
          c.company_name = p_value

        when 'firm' then
          o.firm = p_value

        when 'state' then
          coalesce(
            nullif(btrim(c.state), ''),
            'Not specified'
          ) = p_value

        when 'city' then
          coalesce(
            nullif(btrim(c.city), ''),
            'Not specified'
          ) = p_value

        when 'agent' then
          coalesce(
            nullif(btrim(c.agent), ''),
            'Not specified'
          ) = p_value

        when 'category' then
          coalesce(
            nullif(btrim(i.category_snapshot), ''),
            'Not specified'
          ) = p_value

        when 'style' then
          coalesce(
            nullif(btrim(i.style_snapshot), ''),
            'Not specified'
          ) = p_value

        when 'fabric' then
          coalesce(
            nullif(btrim(i.fabric_snapshot), ''),
            'Not specified'
          ) = p_value

        when 'source' then
          coalesce(
            nullif(btrim(i.last_modified_by_type), ''),
            'unknown'
          ) = p_value

        else false
      end
    );

  select jsonb_build_object(
    'pieces',
      coalesce(sum(pieces), 0)::integer,

    'sets',
      coalesce(sum(sets), 0)::integer,

    'customers',
      count(distinct customer_id)::integer,

    'designs',
      count(distinct design_no)::integer,

    'orders',
      count(distinct order_id)::integer
  )
  into v_summary
  from _dashboard_drill_facts;

  select coalesce(
    jsonb_agg(
      to_jsonb(x)
      order by x.pieces desc, x."companyName"
    ),
    '[]'::jsonb
  )
  into v_customers
  from (
    select
      customer_id::text as "customerId",
      company_name as "companyName",
      min(contact_name) as "contactName",
      min(phone_e164) as phone,
      min(city) as city,
      min(state) as state,
      min(agent) as agent,
      sum(sets)::integer as sets,
      sum(pieces)::integer as pieces,
      count(distinct design_no)::integer as designs,
      count(distinct order_id)::integer as orders
    from _dashboard_drill_facts
    group by customer_id, company_name
  ) x;

  select coalesce(
    jsonb_agg(
      to_jsonb(x)
      order by x.pieces desc, x."designNo"
    ),
    '[]'::jsonb
  )
  into v_designs
  from (
    select
      design_no as "designNo",
      min(firm) as firm,
      min(category) as category,
      min(style) as style,
      min(fabric) as fabric,
      sum(sets)::integer as sets,
      sum(pieces)::integer as pieces,
      count(distinct customer_id)::integer as customers,
      count(distinct order_id)::integer as orders
    from _dashboard_drill_facts
    group by design_no
  ) x;

  return jsonb_build_object(
    'dimension', p_dimension,
    'label', p_value,
    'summary', v_summary,
    'customerDetails', v_customers,
    'designDetails', v_designs
  );
end;
$$;

revoke all on function public.admin_dashboard_drill_v1(
  text,
  text,
  jsonb,
  text
) from public, anon;

grant execute on function public.admin_dashboard_drill_v1(
  text,
  text,
  jsonb,
  text
) to authenticated;
