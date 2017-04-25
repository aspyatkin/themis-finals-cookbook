from sentry.utils.runner import configure
configure()

from sentry.models import (
    Organization,
    Team,
    Project,
    User,
    OrganizationMember,
    OrganizationMemberTeam
)
import os


def create_organization(name):
    model = None
    records = Organization.objects.filter(name=name)
    if len(records) > 0:
        model = records[0]
    else:
        model = Organization()
        model.name = name
        model.save()

    return model


def create_team(name, organization):
    model = None
    records = Team.objects.filter(name=name, organization_id=organization.id)
    if len(records) > 0:
        model = records[0]
    else:
        model = Team()
        model.name = name
        model.organization = organization
        model.save()

    return model


def create_project(name, team, organization):
    model = None
    records = Project.objects.filter(
        name=name,
        team_id=team.id,
        organization_id=organization.id
    )
    if len(records) > 0:
        model = records[0]
    else:
        model = Project()
        model.name = name
        model.team = team
        model.organization = organization
        model.save()

    return model


def create_user(username, password, admin=False):
    model = None
    records = User.objects.filter(username=username)
    if len(records) > 0:
        model = records[0]
    else:
        model = User()
        model.username = username
        model.is_superuser = admin
        model.set_password(password)
        model.save()

    return model


def add_organization_member(user, organization):
    model = None
    records = OrganizationMember.objects.filter(
        user_id=user.id,
        organization_id=organization.id
    )
    if len(records) > 0:
        model = records[0]
    else:
        model = OrganizationMember()
        model.user = user
        model.organization = organization
        model.role = 'owner' if user.is_superuser else 'member'
        model.save()

    return model


def add_team_member(organization_member, team):
    model = None
    records = OrganizationMemberTeam.objects.filter(
        organizationmember_id=organization_member.id,
        team_id=team.id
    )
    if len(records) > 0:
        model = records[0]
    else:
        model = OrganizationMemberTeam()
        model.organizationmember = organization_member
        model.team = team
        model.save()

    return model


def find_team(name, teams):
    records = filter(lambda x: x.name == name, teams)
    if len(records) == 1:
        return records[0]
    raise Exception('Team {0} does not exist!'.format(name))


def parse_projects():
    s = os.getenv('THEMIS_FINALS_SENTRY_PROJECTS', '')
    l1 = [x for x in s.split(';') if x]
    l2 = [x.split(':') for x in l1]
    l3 = [[x[0], [y for y in x[1].split(',') if y]] for x in l2]
    return dict(l3)


def parse_admins():
    s = os.getenv('THEMIS_FINALS_SENTRY_ADMINS', '')
    l1 = [x for x in s.split(';') if x]
    l2 = [x.split(':') for x in l1]
    return dict(l2)


def parse_users():
    s = os.getenv('THEMIS_FINALS_SENTRY_USERS', '')
    l1 = [x for x in s.split(';') if x]
    l2 = [x.split(':') for x in l1]
    return dict(l2)


def main():
    organization_name = os.getenv('THEMIS_FINALS_SENTRY_ORGANIZATION', None)
    if organization_name is None:
        raise Exception('Organization name not defined!')
    organization = create_organization(organization_name)

    team_names = [x for x in os.getenv('THEMIS_FINALS_SENTRY_TEAMS', '').split(';') if x]
    if len(team_names) == 0:
        raise Exception('No teams are defined!')

    teams = []
    for team_name in team_names:
        teams.append(create_team(team_name, organization))

    projects = parse_projects()
    if len(projects) == 0:
        raise Exception('No projects are defined!')

    for team_name, team_projects in projects.iteritems():
        team = find_team(team_name, teams)
        for project_name in team_projects:
            create_project(project_name, team, organization)

    admins = parse_admins()
    if len(admins) == 0:
        raise Exception('No admins are defined!')

    for username, password in admins.iteritems():
        admin = create_user(username, password, admin=True)
        org_member = add_organization_member(admin, organization)
        for team in teams:
            add_team_member(org_member, team)

    users = parse_users()
    if len(users) == 0:
        raise Exception('No users are defined!')

    for username, password in users.iteritems():
        user = create_user(username, password)
        org_member = add_organization_member(user, organization)
        for team in teams:
            add_team_member(org_member, team)


if __name__ == '__main__':
    main()
