
ALTER TABLE financeiro.mapeamento_categorias
ADD CONSTRAINT mapeamento_categorias_empresa_codigo_unique
UNIQUE (empresa, codigo_omie);
