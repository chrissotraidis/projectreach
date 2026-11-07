/* Native modal/UIKit focus, serialized by xg_ios.m's pad_lock. */
#ifndef XG_FOCUS_INPUT_H
#define XG_FOCUS_INPUT_H

struct xg_focus_input {
	int active;
	int announced;
	int lost;
};
#define XG_FOCUS_INPUT_INITIALIZER { 0, -1, 0 }

static inline void xg_focus_created(struct xg_focus_input *focus)
{
	focus->announced = -1;
}

static inline void xg_focus_set(struct xg_focus_input *focus, int active)
{
	active = !!active;
	if (focus->active && !active) focus->lost = 1;
	focus->active = active;
}

/* A rapid loss/regain must still deliver the loss before the new gain. This
 * state is independent of the bounded key queue, so a full queue cannot drop it. */
static inline int xg_focus_next(struct xg_focus_input *focus, int *active)
{
	if (!focus->lost && focus->active == focus->announced) return 0;
	*active = focus->lost ? 0 : focus->active;
	focus->lost = 0;
	focus->announced = *active;
	return 1;
}

#endif
