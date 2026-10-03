import { OpenApiGeneratorV31, type OpenAPIRegistry } from '@asteasolutions/zod-to-openapi'
import type { Express } from 'express'
import swaggerUi from 'swagger-ui-express'

/** The OpenAPI document for every route registered so far. */
export function openApiDocument(registry: OpenAPIRegistry, prefix: string) {
  return new OpenApiGeneratorV31(registry.definitions).generateDocument({
    openapi: '3.1.0',
    info: { title: 'Saba API', version: '0.1.0' },
    servers: [{ url: prefix }],
  })
}

/** {prefix}/openapi.json and the Swagger UI at {prefix}/docs. Call after every route is added. */
export function serveDocs(app: Express, registry: OpenAPIRegistry, prefix: string): void {
  const document = openApiDocument(registry, prefix)
  app.get(`${prefix}/openapi.json`, (_req, res) => {
    res.json(document)
  })
  app.use(`${prefix}/docs`, swaggerUi.serve, swaggerUi.setup(document))
}
