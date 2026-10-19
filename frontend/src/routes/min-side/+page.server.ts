import type { PageServerLoad } from './$types';
import { backendUserFetcher } from '$lib/server/backendApi';

export const load: PageServerLoad = async (event) => {
    const api = backendUserFetcher(event);
    const [minSideRes, lookupRes] = await Promise.all([
        api("/overview/min_side"),
        api("/lookup/all"),
    ]);

    const minSide = minSideRes.ok ? await minSideRes.json() : [];
    const lookup = lookupRes.ok ? await lookupRes.json() : {};

    return {
        minSide,
        koerselstyper:       lookup.koerselstyper         ?? [],
        statuser:            lookup.statuser               ?? [],
        skolematrikler:      lookup.skolematrikler         ?? [],
        sagsbehandlere:      lookup.sagsbehandlere         ?? [],
        pprSagsbehandlere:   lookup.ppr_sagsbehandlere    ?? [],
        tidspunkter:         lookup.tidspunkter            ?? [],
        hjemler:             lookup.hjemler                ?? [],
        afgoerelsesbreve:    lookup.afgoerelsesbreve       ?? [],
        koerselstypeTillaeg: lookup.koerselstypeTillaeg    ?? [],
        dage:                lookup.dage                   ?? [],
        hjaelpemidler:       lookup.hjaelpemidler          ?? [],
        ungdomsuddannelser:  lookup.ungdomsuddannelser      ?? [],
        rutetyper:           lookup.rutetyper              ?? [],
    };
};