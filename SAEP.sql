CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE colaboradores (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    senha TEXT NOT NULL,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    data_cadastro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE categorias (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE tarefas (
    id SERIAL PRIMARY KEY,
    colaborador_id INT NOT NULL REFERENCES colaboradores(id) ON DELETE CASCADE,
    categoria_id INT NOT NULL REFERENCES categorias(id) ON DELETE CASCADE,
    titulo VARCHAR(150) NOT NULL,
    descricao TEXT,
    prazo_entrega DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDENTE' CHECK (status IN ('PENDENTE', 'EM ANDAMENTO', 'CONCLUIDO', 'CANCELADO')),
    data_criacao TIMESTAMP
);

CREATE TABLE historico_tarefas (
    id SERIAL PRIMARY KEY,
    tarefa_id INT REFERENCES tarefas(id) ON DELETE CASCADE,
    acao VARCHAR(100) NOT NULL,
    detalhes TEXT,
    data_historico TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION fn_validar_e_registrar_tarefa()
RETURNS TRIGGER AS $$
DECLARE
    v_ativo BOOLEAN;
BEGIN
    SELECT ativo INTO v_ativo
    FROM colaboradores
    WHERE id = NEW.colaborador_id;

    IF v_ativo IS NOT TRUE THEN
        RAISE EXCEPTION 'Erro: O colaborador (ID %) não está ativo ou não existe no sistema.', NEW.colaborador_id;
    END IF;

    IF NEW.data_criacao IS NULL THEN
        NEW.data_criacao := CURRENT_TIMESTAMP;
    END IF;

    IF NEW.id IS NULL THEN
        NEW.id := nextval(pg_get_serial_sequence('tarefas', 'id'));
    END IF;

    INSERT INTO historico_tarefas (tarefa_id, acao, detalhes)
    VALUES (NEW.id, 'CRIAÇÃO DE TAREFA', CONCAT('Tarefa "', NEW.titulo, '" criada e vinculada ao colaborador ID ', NEW.colaborador_id));

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_tarefa
BEFORE INSERT ON tarefas
FOR EACH ROW
EXECUTE FUNCTION fn_validar_e_registrar_tarefa();

INSERT INTO colaboradores (nome, email, senha, ativo) VALUES
('Ana Silva', 'ana.silva@empresa.com', crypt('Senha123#', gen_salt('bf')), TRUE),
('Carlos Oliver', 'carlos.oliver@empresa.com', crypt('Senha456#', gen_salt('bf')), TRUE),
('Mariana Costa', 'mariana.costa@empresa.com', crypt('Senha789#', gen_salt('bf')), FALSE);

INSERT INTO categorias (nome) VALUES
('Desenvolvimento'),
('Infraestrutura'),
('Design & UX');

INSERT INTO tarefas (colaborador_id, categoria_id, titulo, descricao, prazo_entrega, status) VALUES
(1, 1, 'Criar API REST de Autenticação', 'Desenvolver endpoints de login seguro com JWT', CURRENT_DATE + INTERVAL '2 days', 'EM ANDAMENTO'),
(2, 2, 'Migração de Servidor PostgreSQL', 'Atualizar versão do banco de dados em produção', CURRENT_DATE + INTERVAL '1 day', 'PENDENTE'),
(1, 3, 'Redesign da Landing Page', 'Ajustar layout para responsividade móvel', CURRENT_DATE + INTERVAL '5 days', 'PENDENTE');

INSERT INTO historico_tarefas (tarefa_id, acao, detalhes) VALUES
(1, 'ATUALIZAÇÃO DE STATUS', 'Status alterado de PENDENTE para EM ANDAMENTO por Ana Silva');

CREATE OR REPLACE FUNCTION fn_autenticar_usuario(
    p_email VARCHAR,
    p_senha VARCHAR
)
RETURNS TABLE (
    autenticado BOOLEAN,
    mensagem TEXT,
    colaborador_id INT,
    colaborador_nome VARCHAR
) AS $$
DECLARE
    v_colaborador colaboradores%ROWTYPE;
BEGIN
    SELECT * INTO v_colaborador
    FROM colaboradores
    WHERE email = p_email;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'E-mail incorreto ou não cadastrado.'::TEXT, NULL::INT, NULL::VARCHAR;
        RETURN;
    END IF;

    IF v_colaborador.ativo IS FALSE THEN
        RETURN QUERY SELECT FALSE, 'Acesso negado: colaborador inativo.'::TEXT, NULL::INT, NULL::VARCHAR;
        RETURN;
    END IF;

    IF v_colaborador.senha = crypt(p_senha, v_colaborador.senha) THEN
        RETURN QUERY SELECT TRUE, 'Autenticação realizada com sucesso.'::TEXT, v_colaborador.id, v_colaborador.nome;
    ELSE
        RETURN QUERY SELECT FALSE, 'Senha incorreta.'::TEXT, NULL::INT, NULL::VARCHAR;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW vw_painel_principal AS
SELECT 
    c.nome AS colaborador_nome,
    t.titulo AS titulo_tarefa,
    cat.nome AS categoria,
    t.prazo_entrega,
    t.status AS status_atividade
FROM tarefas t
JOIN colaboradores c ON t.colaborador_id = c.id
JOIN categorias cat ON t.categoria_id = cat.id;

CREATE OR REPLACE FUNCTION fn_buscar_colaboradores(p_termo TEXT)
RETURNS TABLE (
    id INT,
    nome VARCHAR,
    email VARCHAR,
    ativo BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.nome,
        c.email,
        c.ativo
    FROM colaboradores c
    WHERE c.nome ILIKE '%' || p_termo || '%'
       OR c.email ILIKE '%' || p_termo || '%';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW vw_cronograma_prazos AS
SELECT 
    t.titulo AS titulo_tarefa,
    t.status AS status_tarefa,
    (t.prazo_entrega - CURRENT_DATE) AS dias_restantes,
    c.nome AS responsavel,
    t.prazo_entrega
FROM tarefas t
JOIN colaboradores c ON t.colaborador_id = c.id
ORDER BY t.prazo_entrega ASC;
