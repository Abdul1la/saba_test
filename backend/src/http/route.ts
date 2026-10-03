import type { OpenAPIRegistry } from '@asteasolutions/zod-to-openapi'
import type { Request, Response, Router } from 'express'
import { z } from 'zod'
import type { SessionUser, Who } from './auth.js'
import { envelopeOf, ErrorBody, ok } from './envelope.js'
import { parseInput } from './validate.js'

/** Where routes go: the Express router, and the OpenAPI registry that documents them. */
export interface Api {
  router: Router
  registry: OpenAPIRegistry
  /** Check every answer against its documented schema (never in production). */
  checkResponses: boolean
  /** Sets req.user for [who], or throws 401/403. */
  authenticate(req: Request, who: Exclude<Who, 'public'>): Promise<void>
  /** On a public route: the caller when signed in, else null. */
  identify(req: Request): Promise<SessionUser | null>
}

type Method = 'get' | 'post' | 'put' | 'patch' | 'delete'
type Out<S> = S extends z.ZodType ? z.output<S> : undefined

export interface RouteSpec<
  B extends z.ZodType | undefined,
  Q extends z.ZodObject | undefined,
  P extends z.ZodObject | undefined,
  R extends z.ZodType,
> {
  method: Method
  /** Express form: /orders/:id */
  path: string
  tag: string
  summary: string
  /** Who may call it; checked before the input, so a stranger gets 401, not 422. */
  who: Who
  body?: B
  /** Nested body objects whose field errors are named without the object's own name (`delivery.feeInside` → `feeInside`). */
  flatten?: readonly string[]
  query?: Q
  params?: P
  response: R
  handle(input: {
    req: Request
    res: Response
    body: Out<B>
    query: Out<Q>
    params: Out<P>
  }): Promise<z.input<R> | Page<z.input<R>>>
}

/** App lists: page and perPage in the query (BACKEND_PLAN.md §2.2: 20 a page, at most 100). */
export const PageQuery = z.object({
  page: z.coerce.number().int().min(1).default(1),
  perPage: z.coerce.number().int().min(1).max(100).default(20),
})

/** One page of a list: the rows go in data, the counts in meta (the app's PaginatedList). */
export class Page<T> {
  constructor(
    readonly items: T,
    readonly query: { page: number; perPage: number },
    readonly total: number,
  ) {}

  get meta() {
    const { page, perPage } = this.query
    return { page, perPage, total: this.total, totalPages: Math.ceil(this.total / perPage) }
  }
}

const errorResponse = { content: { 'application/json': { schema: ErrorBody } } }

/**
 * Adds a route and its OpenAPI entry in one call, so the documentation can't
 * drift from what is served. Input is validated before [handle] runs; outside
 * production, the answer is checked against [response] too.
 */
export function route<
  B extends z.ZodType | undefined = undefined,
  Q extends z.ZodObject | undefined = undefined,
  P extends z.ZodObject | undefined = undefined,
  R extends z.ZodType = z.ZodType,
>(api: Api, spec: RouteSpec<B, Q, P, R>): void {
  api.registry.registerPath({
    method: spec.method,
    path: spec.path.replace(/:(\w+)/g, '{$1}'),
    tags: [spec.tag],
    summary: spec.who === 'public' ? spec.summary : `${spec.summary} (${whoLabel(spec.who)})`,
    ...(spec.who !== 'public' && { security: [{ bearer: [] }] }),
    request: {
      ...(spec.body && { body: { content: { 'application/json': { schema: spec.body } } } }),
      ...(spec.query && { query: spec.query }),
      ...(spec.params && { params: spec.params }),
    },
    responses: {
      200: {
        description: 'Success',
        content: { 'application/json': { schema: envelopeOf(spec.response) } },
      },
      default: { description: 'An error, in the contract shape', ...errorResponse },
    },
  })

  api.router[spec.method](spec.path, async (req, res) => {
    if (spec.who !== 'public') await api.authenticate(req, spec.who)
    const input = {
      req,
      res,
      body: (spec.body ? parseInput(spec.body, req.body, spec.flatten) : undefined) as Out<B>,
      query: (spec.query ? parseInput(spec.query, req.query) : undefined) as Out<Q>,
      params: (spec.params ? parseInput(spec.params, req.params) : undefined) as Out<P>,
    }
    const result = await spec.handle(input)
    const [data, meta] = result instanceof Page ? [result.items, result.meta] : [result, {}]
    res.json(ok(api.checkResponses ? spec.response.parse(data) : data, meta))
  })
}

function whoLabel(who: Exclude<Who, 'public'>): string {
  return who === 'signedIn' ? 'signed in' : who.map((role) => role.toLowerCase()).join(', ')
}
