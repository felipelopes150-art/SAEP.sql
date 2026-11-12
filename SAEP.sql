
create table funcionarios (
    id serial primary key,
    nome varchar(100) not null,
    email varchar(100) not null unique,
    senha text not null,
    ativo boolean not null default true,
    data_cadastro timestamp not null default current_timestamp
);

create table tipos (
    id serial primary key,
    nome varchar(50) not null unique
);

create table atividades (
    id serial primary key,
    funcionario_id int not null references funcionarios(id) on delete cascade,
    tipo_id int not null references tipos(id) on delete cascade,
    titulo varchar(150) not null,
    descricao text,
    prazo_entrega date not null,
    status varchar(20) not null default 'PENDENTE' check (status in ('PENDENTE', 'EM ANDAMENTO', 'CONCLUIDO', 'CANCELADO')),
    data_criacao timestamp not null default current_timestamp
);

create table registros_atividades (
    id serial primary key,
    atividade_id int references atividades(id) on delete cascade,
    acao varchar(100) not null,
    detalhes text,
    data_registro timestamp not null default current_timestamp
);

create or replace function fn_conferir_atividade()
returns trigger as $$
declare
    v_ativo boolean;
begin
    select ativo into v_ativo
    from funcionarios
    where id = new.funcionario_id;

    if v_ativo is not true then
        raise exception 'Erro: O funcionario (ID %) nao esta ativo ou nao existe no sistema.', new.funcionario_id;
    end if;

    if new.data_criacao is null then
        new.data_criacao := current_timestamp;
    end if;

    return new;
end;
$$ language plpgsql;

create trigger trg_conferir_atividade
before insert on atividades
for each row
execute function fn_conferir_atividade();

create or replace function fn_anotar_atividade()
returns trigger as $$
begin
    insert into registros_atividades (atividade_id, acao, detalhes)
    values (
        new.id,
        'CRIACAO DE ATIVIDADE',
        concat('Atividade "', new.titulo, '" criada e vinculada ao funcionario ID ', new.funcionario_id)
    );

    return new;
end;
$$ language plpgsql;

create trigger trg_anotar_atividade
after insert on atividades
for each row
execute function fn_anotar_atividade();

insert into funcionarios (nome, email, senha, ativo) values
('Ana Silva', 'ana.silva@empresa.com', 'Senha123#', true),
('Carlos Oliver', 'carlos.oliver@empresa.com', 'Senha456#', true),
('Mariana Costa', 'mariana.costa@empresa.com', 'Senha789#', false);

insert into tipos (nome) values
('Desenvolvimento'),
('Infraestrutura'),
('Design & UX');

insert into atividades (funcionario_id, tipo_id, titulo, descricao, prazo_entrega, status) values
(1, 1, 'Criar API REST de Autenticacao', 'Desenvolver endpoints de login seguro com JWT', current_date + interval '2 days', 'EM ANDAMENTO'),
(2, 2, 'Migracao de Servidor PostgreSQL', 'Atualizar versao do banco de dados em producao', current_date + interval '1 day', 'PENDENTE'),
(1, 3, 'Redesign da Landing Page', 'Ajustar layout para responsividade movel', current_date + interval '5 days', 'PENDENTE');

insert into registros_atividades (atividade_id, acao, detalhes) values
(1, 'ATUALIZACAO DE STATUS', 'Status alterado de PENDENTE para EM ANDAMENTO por Ana Silva');

create or replace function fn_verificar_acesso(
    p_email varchar,
    p_senha varchar
)
returns table (
    autenticado boolean,
    mensagem text,
    funcionario_id int,
    funcionario_nome varchar
) as $$
declare
    v_funcionario funcionarios%rowtype;
begin
    select * into v_funcionario
    from funcionarios
    where email = p_email;

    if not found then
        return query select false, 'E-mail incorreto ou nao cadastrado.'::text, null::int, null::varchar;
        return;
    end if;

    if v_funcionario.ativo is false then
        return query select false, 'Acesso negado: funcionario inativo.'::text, null::int, null::varchar;
        return;
    end if;

    if v_funcionario.senha = p_senha then
        return query select true, 'Verificacao realizada com sucesso.'::text, v_funcionario.id, v_funcionario.nome;
    else
        return query select false, 'Senha incorreta.'::text, null::int, null::varchar;
    end if;
end;
$$ language plpgsql;

create or replace view vw_resumo_geral as
select
    f.nome as funcionario_nome,
    a.titulo as titulo_atividade,
    tp.nome as tipo,
    a.prazo_entrega,
    a.status as status_atividade
from atividades a
join funcionarios f on a.funcionario_id = f.id
join tipos tp on a.tipo_id = tp.id;

create or replace function fn_localizar_funcionarios(p_termo text)
returns table (
    id int,
    nome varchar,
    email varchar,
    ativo boolean
) as $$
begin
    return query
    select
        f.id,
        f.nome,
        f.email,
        f.ativo
    from funcionarios f
    where f.nome ilike '%' || p_termo || '%'
       or f.email ilike '%' || p_termo || '%';
end;
$$ language plpgsql;

create or replace view vw_agenda_prazos as
select
    a.titulo as titulo_atividade,
    a.status as status_atividade,
    (a.prazo_entrega - current_date) as dias_restantes,
    f.nome as responsavel,
    a.prazo_entrega
from atividades a
join funcionarios f on a.funcionario_id = f.id
order by a.prazo_entrega asc;

